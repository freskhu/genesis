#!/usr/bin/env bash
# post-delegation.sh — BLOCKING reflective-artifact gate after Agent delegation
#
# Event: PostToolUse (matcher: Task)
#
# CHOSEN RULE (ported peer pattern — per-deliverable blocking pre-flight gate):
#   After a Task/Agent delegation completes, a *reflective artifact* must exist
#   for the work in this window before the orchestrator is allowed to continue.
#   The artifact is EITHER:
#     - a `diary_entries` row  (palace.py diary-write — the agent's reflection), OR
#     - an `activity_history` row  (delegation/handoff recorded).
#   Window = last 12 minutes (covers a normal delegate→extract→record cycle).
#
#   - Artifact EXISTS  → pass cleanly (exit 0). LOOP-FREE: once the orchestrator
#                        records the diary/handoff, the same hook on the next turn
#                        sees the fresh row and stops blocking. No flip-flop.
#   - Artifact MISSING → escalate from soft reminder to BLOCKING: print a clear
#                        stderr instruction and exit 2 (PostToolUse exit 2 feeds
#                        stderr back to the model and forces it to act before
#                        proceeding).
#
# Idempotency: if a fresh llm_calls row exists (<5 min), the call was already
#   logged this cycle → quiet exit 0 (do not block; logging is the gated step
#   and it is done).
#
# Fail-open: missing DB / sqlite3 / jq, or any tooling error → exit 0 silently.
#   This gate NEVER hard-fails on infrastructure. It only blocks when it can
#   positively prove the reflective artifact is absent.
#
# Performance budget: <300ms (single bail'd sqlite3 invocation, 2s timeout).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || exit 0
DB="$SCRIPT_DIR/Database/team.db"

INPUT=$(cat 2>/dev/null || true)

# --- Scope guard: only act on Task/Agent delegations -----------------------
TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
    TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
fi
if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "Task" ] && [ "$TOOL_NAME" != "Agent" ]; then
    exit 0
fi

# --- Fail-open preconditions ------------------------------------------------
[ -f "$DB" ] || exit 0
command -v sqlite3 >/dev/null 2>&1 || exit 0

# --- Idempotency: fresh llm_calls row → gated step already done -------------
RECENT_LLM=$(sqlite3 -bail -cmd ".timeout 2000" "$DB" \
    "SELECT COUNT(*) FROM llm_calls WHERE created_at > datetime('now','-5 minutes');" \
    2>/dev/null | tail -n 1)
[ -z "$RECENT_LLM" ] && RECENT_LLM=0
case "$RECENT_LLM" in ''|*[!0-9]*) RECENT_LLM=0 ;; esac
if [ "$RECENT_LLM" -ge 1 ]; then
    exit 0
fi

# --- Reflective-artifact check: diary OR activity within 12 minutes ---------
ARTIFACT=$(sqlite3 -bail -cmd ".timeout 2000" "$DB" \
    "SELECT
       (SELECT COUNT(*) FROM diary_entries
          WHERE datetime(created_at) > datetime('now','-12 minutes'))
     + (SELECT COUNT(*) FROM activity_history
          WHERE datetime(occurred_at) > datetime('now','-12 minutes'));" \
    2>/dev/null | tail -n 1)
[ -z "$ARTIFACT" ] && ARTIFACT=""           # empty = query failed → fail-open
case "$ARTIFACT" in
    ''|*[!0-9]*) exit 0 ;;                   # non-numeric / error → fail-open
esac

if [ "$ARTIFACT" -ge 1 ]; then
    # Reflective artifact present for this window. Loop-free clean pass.
    exit 0
fi

# --- No artifact → BLOCK ----------------------------------------------------
cat >&2 <<'EOF'
BLOCKING: a Task/Agent delegation just completed but NO reflective artifact
exists for this work window (no diary_entries or activity_history row in the
last 12 minutes).

Before continuing you MUST record the delegated agent's reflection / handoff:
  1) Obtain the agent's diary entry or HANDOFF from its result.
  2) Persist it — EITHER:
       palace.py diary-write "<AgentName>" "SESSION:<date>|<key.facts>|<rating>" --topic "<topic>"
     OR insert an activity_history row capturing the delegation/handoff.
  3) Also log the llm_calls row (see .claude/protocols/llm-logging.md).

While you are here, close the procedural-memory loop too (NOT gated by this
hook, but it is the moment where it is cheapest):
  - REUSED an existing pattern? Increment it now, by the id you noted when you
    queried it:
      sqlite3 Database/team.db "UPDATE procedural_memory
        SET success_count = success_count + 1,
            last_used_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')
        WHERE id = <ID>;"
    (use failure_count instead when the pattern was followed and did not work)
  - NEW non-obvious pattern? Capture it with palace.py proc-record — never a
    hand-written INSERT (that leaves dedup_key NULL and the row can never be
    incremented again).
  See .claude/protocols/procedural-memory.md

This gate clears automatically once a fresh diary_entries OR activity_history
row exists — re-run will pass. Do this NOW, while the result is fresh.
EOF

exit 2
