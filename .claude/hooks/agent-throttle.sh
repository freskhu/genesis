#!/usr/bin/env bash
# agent-throttle.sh -- PreToolUse (Agent|Task): warns when an agent is already running.
#
# Why it exists: "one agent at a time" kept only in memory does not stop a burst of
# dispatches in one hour that can exhaust the session budget. The goal is NOT to stop work; it
# is to give the orchestrator a signal before it stacks another wave.
#
# Mode: WARN by default. It never blocks; the warning goes back as additionalContext and
# the dispatch decision stays with the orchestrator. Rate-based legs (calls per hour,
# tokens) were tried and removed: they warned on almost every dispatch and changed none.
# What stays is the in-flight signal.
#
# Signal: activity_history rows written by the orchestrator around each dispatch
# (`delegation_dispatched` before, `delegation_completed` after; see
# .claude/protocols/llm-logging.md). More dispatched than completed in the last
# INFLIGHT_WINDOW_MIN minutes = an agent is still running.
#
# Contract:
#   MODE=warn  -> exit 0 always; warning via hookSpecificOutput.additionalContext
#   MODE=block -> exit 2 + stderr (kept for whoever wants a hard stop; off by default)
# Fail-open: any error (no sqlite3, missing or locked DB, non-numeric output) lets the
# dispatch through and logs the reason.
#
# DB access is ALWAYS read-only (mode=ro, or immutable=1 for a closed DB with no WAL
# pending) with a busy timeout. See .claude/rules/personal-data-db-access.md, section 3.
# Test: .claude/hooks/agent-throttle.test.sh

# ---- Mode (the only line to change to block again) ----
MODE=warn
# -------------------------------------------------------

INFLIGHT_WINDOW_MIN=30
SQLITE_TIMEOUT_MS=5000

LOG_FILE="${GENESIS_LOG_DIR:-$HOME/.mempalace/logs}/agent-throttle.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

allow() { log "ALLOW $1"; exit 0; }

# warn <log-line> <message-for-the-agent>
warn() {
  if [ "$MODE" = "block" ]; then
    log "BLOCK $1"
    echo "BLOCKED (agent-throttle): $2" >&2
    exit 2
  fi
  log "WARN $1"
  payload="AGENT-THROTTLE (warning, not a block): $2 Check whether this dispatch is needed right now; if it can wait, wait."
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$payload" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx},systemMessage:$ctx}'
  else
    esc=$(printf '%s' "$payload" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"},"systemMessage":"%s"}' "$esc" "$esc"
  fi
  exit 0
}

INPUT=$(cat 2>/dev/null || true)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in
  Agent|Task|"") : ;;              # "" = manual run / test
  *) exit 0 ;;                      # another tool: not ours
esac

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // .tool_input.description // empty' 2>/dev/null || true)
SUBAGENT="${SUBAGENT:-?}"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DB="${TEAM_DB:-$PROJECT_DIR/Database/team.db}"
command -v sqlite3 >/dev/null 2>&1 || allow "fail-open: sqlite3 not found subagent=$SUBAGENT"
[ -f "$DB" ] || allow "fail-open: no DB ($DB) subagent=$SUBAGENT"

# In WAL mode a reader needs the -shm file, and with mode=ro SQLite cannot create it: a
# closed, clean DB fails with error 14 on the first query. With no -shm and an absent or
# empty -wal there is no pending write, so immutable=1 is safe (it never writes).
URI="file:$DB?mode=ro"
if [ ! -f "$DB-shm" ] && [ ! -s "$DB-wal" ]; then
  URI="file:$DB?immutable=1"
fi

QERRF=$(mktemp "${TMPDIR:-/tmp}/agent-throttle.XXXXXX" 2>/dev/null) || QERRF=""
trap '[ -n "$QERRF" ] && rm -f "$QERRF"' EXIT

# Returns the last line of the result and 0; returns 1 if sqlite3 fails. The exit code is
# the only defence against the CLI echoing the PRAGMA value on stdout.
q() {
  local out rc
  out=$(sqlite3 -readonly -separator '|' "$URI" \
    "PRAGMA busy_timeout=$SQLITE_TIMEOUT_MS;" "$1" 2>"${QERRF:-/dev/null}")
  rc=$?
  [ "$rc" -eq 0 ] || return 1
  printf '%s\n' "$out" | tail -n 1
}

qerr() { [ -n "$QERRF" ] && head -n 1 "$QERRF" 2>/dev/null | tr -d '\n' | cut -c1-120; }

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

ROW=$(q "
  SELECT
    (SELECT COUNT(*) FROM activity_history
      WHERE action='delegation_dispatched'
        AND occurred_at >= strftime('%Y-%m-%dT%H:%M:%SZ','now','-$INFLIGHT_WINDOW_MIN minutes')),
    (SELECT COUNT(*) FROM activity_history
      WHERE action='delegation_completed'
        AND occurred_at >= strftime('%Y-%m-%dT%H:%M:%SZ','now','-$INFLIGHT_WINDOW_MIN minutes')),
    COALESCE((SELECT COALESCE(strftime('%H:%M', datetime(occurred_at,'localtime')), substr(occurred_at,12,5))
      FROM activity_history WHERE action='delegation_dispatched'
        AND occurred_at >= strftime('%Y-%m-%dT%H:%M:%SZ','now','-$INFLIGHT_WINDOW_MIN minutes')
      ORDER BY occurred_at DESC LIMIT 1),'??:??'),
    COALESCE((SELECT substr(replace(replace(summary,char(10),' '),'|','/'),1,100)
      FROM activity_history WHERE action='delegation_dispatched'
        AND occurred_at >= strftime('%Y-%m-%dT%H:%M:%SZ','now','-$INFLIGHT_WINDOW_MIN minutes')
      ORDER BY occurred_at DESC LIMIT 1),'(no summary)');
") || allow "fail-open: in-flight query failed ($(qerr)) subagent=$SUBAGENT"
[ -n "$ROW" ] || allow "fail-open: in-flight query returned nothing (DB locked?) subagent=$SUBAGENT"

DISPATCHED=$(printf '%s' "$ROW" | cut -d'|' -f1)
COMPLETED=$(printf '%s' "$ROW" | cut -d'|' -f2)
SINCE=$(printf '%s' "$ROW" | cut -d'|' -f3)
LAST_SUMMARY=$(printf '%s' "$ROW" | cut -d'|' -f4-)
if ! is_num "$DISPATCHED" || ! is_num "$COMPLETED"; then
  allow "fail-open: non-numeric in-flight count ('$ROW') subagent=$SUBAGENT"
fi

if [ "$DISPATCHED" -gt "$COMPLETED" ]; then
  warn "rule=inflight dispatched=$DISPATCHED completed=$COMPLETED window=${INFLIGHT_WINDOW_MIN}min subagent=$SUBAGENT" \
"an agent has been running since $SINCE: $LAST_SUMMARY."
fi

allow "inflight=$DISPATCHED/$COMPLETED subagent=$SUBAGENT"
