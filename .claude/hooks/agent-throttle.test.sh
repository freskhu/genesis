#!/usr/bin/env bash
# agent-throttle.test.sh -- test battery for agent-throttle.sh on temporary synthetic DBs.
# Run: bash .claude/hooks/agent-throttle.test.sh   Exit 0 = all pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/agent-throttle.sh}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/throttle-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export GENESIS_LOG_DIR="$TMP/logs"
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
run() { printf '{"tool_name":"%s","tool_input":{"subagent_type":"x"}}' "${1:-Agent}" | bash "$HOOK" 2>/dev/null; }
# a fresh DB per scenario, with only the table the scenario needs
db() { export TEAM_DB="$TMP/$1.db"; sqlite3 "$TEAM_DB" "CREATE TABLE activity_history(action TEXT,occurred_at TEXT,summary TEXT);" >/dev/null; }
row() { sqlite3 "$TEAM_DB" "INSERT INTO activity_history VALUES('$1',strftime('%Y-%m-%dT%H:%M:%SZ','now','$2'),'$3');"; }

[ -x "$HOOK" ] && ok "hook is executable" || ko "hook is not executable"

db empty
OUT=$(run); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "no agent running: silence" || ko "no agent running"

db rate
sqlite3 "$TEAM_DB" "CREATE TABLE llm_calls(id INTEGER PRIMARY KEY,created_at TEXT); WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<30) INSERT INTO llm_calls(created_at) SELECT datetime('now') FROM n;"
OUT=$(run); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "30 calls in the last hour do not warn (no rate leg)" || ko "rate leg still warns"

db running
row delegation_dispatched '-5 minutes' 'test dispatch'
OUT=$(run); RC=$?
[ "$RC" = 0 ] && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext|test("agent has been running")' >/dev/null && ok "agent running warns, exit 0" || ko "agent running"

OUT=$(run Bash); [ -z "$OUT" ] && ok "another tool: out of scope" || ko "another tool"

row delegation_completed '-1 minutes' 'done'
OUT=$(run); [ -z "$OUT" ] && ok "agent completed: silence" || ko "agent completed"

db old
row delegation_dispatched '-60 minutes' 'old dispatch'
OUT=$(run); [ -z "$OUT" ] && ok "dispatch outside the 30 min window: silence" || ko "outside the window"

export TEAM_DB=/does/not/exist
OUT=$(run); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "fail-open without DB" || ko "fail-open without DB"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
