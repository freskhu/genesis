#!/usr/bin/env bash
# force-session-end.sh — Enforces the Session End Protocol
#
# Event: Stop
# Purpose: When the assistant attempts to end the session, verify that the
#          session-end protocol (lessons + procedural audit + memory-hot
#          regeneration) was followed. If anything critical is missing AND the
#          session had real work, block the Stop with a system reminder
#          pointing to .claude/protocols/session-end.md.
#
# Block conditions (ALL must be true to block):
#   1. Session had >=1 llm_call today OR >=3 activity_history rows today
#      (i.e., real work happened — not a trivial "thanks, see you later")
#   2. AT LEAST ONE of:
#        a) No lessons captured today (action IN lessons_captured,
#           improvement_suggested, session_end)
#        b) No procedural audit today (insert in procedural_memory OR
#           activity_history action='procedural_audit')
#        c) memory-hot.md mtime older than the start of the current session
#           (heuristic: older than the earliest activity_history row today)
#
# Fail-open: if the DB query fails or sqlite3 is missing, allow Stop. Never
# block on tooling errors — log the failure to stderr and exit clean.
#
# Performance budget: <500ms. All queries hit small tables with indexes on
# created_at/occurred_at.

set -u

# Locate repo root (hook is at .claude/hooks/<this file>)
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DB="$SCRIPT_DIR/Database/team.db"
MEMORY_HOT="$SCRIPT_DIR/.claude/memory-hot.md"

# Read hook payload (we don't actually need fields, but consume stdin so the
# pipe closes cleanly).
INPUT=$(cat 2>/dev/null || true)

# Respect stop_hook_active to avoid recursion when our own block re-triggers Stop
STOP_ACTIVE=$(printf '%s' "$INPUT" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('stop_hook_active','false'))
except Exception:
    print('false')" 2>/dev/null)
if [ "$STOP_ACTIVE" = "true" ] || [ "$STOP_ACTIVE" = "True" ]; then
    echo '{}'
    exit 0
fi

# Defensive: missing DB or sqlite3 -> fail open
if [ ! -f "$DB" ] || ! command -v sqlite3 >/dev/null 2>&1; then
    echo "force-session-end: DB or sqlite3 missing, allowing Stop" >&2
    echo '{}'
    exit 0
fi

run_sql() {
    # Single-shot query; suppress stderr (fail-open), default 0 on error.
    # NOTE: We pass busy_timeout via -cmd (not as a SQL statement) so its
    # echoed value doesn't pollute the result. tail -1 belt-and-suspenders.
    local q="$1"
    local result
    result=$(sqlite3 -bail -cmd ".timeout 2000" "$DB" "$q" 2>/dev/null | tail -n 1) || result=""
    [ -z "$result" ] && result=0
    printf '%s' "$result"
}

# 1. Did real work happen today?
LLM_TODAY=$(run_sql "SELECT COUNT(*) FROM llm_calls WHERE created_at > datetime('now','start of day');")
ACT_TODAY=$(run_sql "SELECT COUNT(*) FROM activity_history WHERE occurred_at > datetime('now','start of day');")

# Defensive integer-ish check
case "$LLM_TODAY" in ''|*[!0-9]*) LLM_TODAY=0 ;; esac
case "$ACT_TODAY" in ''|*[!0-9]*) ACT_TODAY=0 ;; esac

if [ "$LLM_TODAY" -lt 1 ] && [ "$ACT_TODAY" -lt 3 ]; then
    # Trivial session — let it close
    echo '{}'
    exit 0
fi

# 2a. Lessons captured?
LESSONS=$(run_sql "SELECT COUNT(*) FROM activity_history WHERE action IN ('lessons_captured','improvement_suggested','session_end') AND occurred_at > datetime('now','start of day');")
case "$LESSONS" in ''|*[!0-9]*) LESSONS=0 ;; esac

# 2b. Procedural audit done?
PROC_NEW=$(run_sql "SELECT COUNT(*) FROM procedural_memory WHERE created_at > datetime('now','start of day');")
PROC_AUDIT=$(run_sql "SELECT COUNT(*) FROM activity_history WHERE action='procedural_audit' AND occurred_at > datetime('now','start of day');")
case "$PROC_NEW" in ''|*[!0-9]*) PROC_NEW=0 ;; esac
case "$PROC_AUDIT" in ''|*[!0-9]*) PROC_AUDIT=0 ;; esac
AUDIT_DONE=$((PROC_NEW + PROC_AUDIT))

# 2c. memory-hot regenerated this session?
# Compare memory-hot mtime against earliest activity_history row today (epoch).
MEMORY_HOT_STALE=0
if [ -f "$MEMORY_HOT" ]; then
    MH_MTIME=$(stat -f %m "$MEMORY_HOT" 2>/dev/null || echo 0)
    SESSION_START_EPOCH=$(run_sql "SELECT CAST(strftime('%s', MIN(occurred_at)) AS INTEGER) FROM activity_history WHERE occurred_at > datetime('now','start of day');")
    case "$SESSION_START_EPOCH" in ''|*[!0-9]*) SESSION_START_EPOCH=0 ;; esac
    # Only flag if we have a real session start and memory-hot is older
    if [ "$SESSION_START_EPOCH" -gt 0 ] && [ "$MH_MTIME" -lt "$SESSION_START_EPOCH" ]; then
        MEMORY_HOT_STALE=1
    fi
else
    MEMORY_HOT_STALE=1
fi

# Build missing-steps list
MISSING=()
[ "$LESSONS" -lt 1 ] && MISSING+=("Step 4 (Lessons Learned) — log via activity_history action lessons_captured/improvement_suggested/session_end")
[ "$AUDIT_DONE" -lt 1 ] && MISSING+=("Step 4.5 (Procedural Audit) — INSERT into procedural_memory OR log action procedural_audit in activity_history")
[ "$MEMORY_HOT_STALE" -eq 1 ] && MISSING+=("Step 5 (Regenerate Memory Hot) — run: python3 scripts/generate_memory_hot.py")

if [ "${#MISSING[@]}" -eq 0 ]; then
    echo '{}'
    exit 0
fi

# Build the block reason as JSON-safe string
REASON_BODY=$(printf '%s\n' "${MISSING[@]}" | python3 -c "
import json, sys
items = [ln.strip() for ln in sys.stdin if ln.strip()]
msg = ('Session End Protocol not followed. Read .claude/protocols/session-end.md and complete the missing steps before closing:\n- '
       + '\n- '.join(items)
       + '\nOnce done, attempt to end again.')
print(json.dumps({'decision': 'block', 'reason': msg}))
" 2>/dev/null)

if [ -z "$REASON_BODY" ]; then
    # JSON build failed — fail open
    echo "force-session-end: failed to build block payload, allowing Stop" >&2
    echo '{}'
    exit 0
fi

printf '%s\n' "$REASON_BODY"
exit 0
