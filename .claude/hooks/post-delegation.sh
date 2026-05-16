#!/usr/bin/env bash
# post-delegation.sh — Reminds the orchestrator to log llm_call + consider procedural capture
#
# Event: PostToolUse (matcher: Task)
# Purpose: After the orchestrator delegates to a subagent via the Task tool,
#          inject a reminder pointing to:
#            - .claude/protocols/llm-logging.md (mandatory INSERT into llm_calls)
#            - .claude/protocols/procedural-memory.md (capture non-obvious patterns)
#
# Strategy: NOT auto-insert. Token counts come from the Agent result and the
#          orchestrator has to extract them. Hook injects a reminder via stderr
#          (visible in the next assistant turn) and exits clean. The hook is
#          idempotent — if an llm_call row was already inserted in the last
#          5 minutes, the reminder is suppressed to avoid noise.
#
# Fail-open: any error (missing DB, jq, sqlite3) just exits 0 silently.
#
# Performance budget: <300ms.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DB="$SCRIPT_DIR/Database/team.db"

INPUT=$(cat 2>/dev/null || true)

# Only fire on Task tool (Agent delegation). If matcher already filtered, this
# is belt-and-suspenders.
TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
    TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
fi
if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "Task" ] && [ "$TOOL_NAME" != "Agent" ]; then
    exit 0
fi

# Idempotency check: skip reminder if a fresh llm_call row exists (<5 min old).
if [ -f "$DB" ] && command -v sqlite3 >/dev/null 2>&1; then
    RECENT=$(sqlite3 -bail -cmd ".timeout 2000" "$DB" "SELECT COUNT(*) FROM llm_calls WHERE created_at > datetime('now','-5 minutes');" 2>/dev/null | tail -n 1)
    [ -z "$RECENT" ] && RECENT=0
    case "$RECENT" in ''|*[!0-9]*) RECENT=0 ;; esac
    if [ "$RECENT" -ge 1 ]; then
        # Already logged something recent. Quiet exit.
        exit 0
    fi
fi

# Emit the reminder. stderr is surfaced back into the agent's context as
# tool output, so the orchestrator sees it on its next turn.
cat >&2 <<'EOF'
POST-DELEGATION REMINDER: a Task call just completed.
1) Log the llm_call row NOW. See .claude/protocols/llm-logging.md for the SQL template (task_id, agent_name, model, tokens, latency_ms, cost_usd).
2) If the approach was non-obvious or reusable, capture it. See .claude/protocols/procedural-memory.md (Step 4.5 of Session End is BLOCKING — easier to log it now while fresh).
3) Extract HANDOFF and KG-FACTS from the agent's result and persist them before moving on.
EOF

exit 0
