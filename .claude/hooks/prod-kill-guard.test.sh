#!/usr/bin/env bash
# prod-kill-guard.test.sh -- test battery for prod-kill-guard.sh with a temporary config.
# Run: bash .claude/hooks/prod-kill-guard.test.sh   Exit 0 = all pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/prod-kill-guard.sh}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/killguard-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
printf '# test\n\ndist/server\nindex\\.js\nmy-service\n' > "$TMP/conf"
export PROTECTED_PROCESSES_CONF="$TMP/conf"
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
run() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; echo $?; }
blocks() { [ "$(run "$2")" = 2 ] && ok "blocks: $1" || ko "blocks: $1"; }
passes() { [ "$(run "$2")" = 0 ] && [ ! -s "$TMP/out" ] && ok "passes: $1" || ko "passes: $1"; }
warns() { [ "$(run "$2")" = 0 ] && grep -q additionalContext "$TMP/out" && ok "warns: $1" || ko "warns: $1"; }

[ -x "$HOOK" ] && ok "hook is executable" || ko "hook is not executable"

blocks "pkill -f on the server entry point" 'pkill -f "dist/server/index.js"'
blocks "killall by protected name" 'killall my-service'
blocks "kill fed by pgrep -f" 'kill $(pgrep -f "dist/server")'
blocks "pgrep -f piped to xargs kill" 'pgrep -f index.js | xargs kill'
blocks "second segment after &&" 'ls && pkill -f my-service'
grep -q 'by PID' "$TMP/err" && ok "message points to stopping by PID" || ko "no PID hint"

warns "pgrep -f alone" 'pgrep -f "dist/server"'
passes "pkill of an unprotected pattern" 'pkill -f my-own-test-script.sh'
passes "kill by PID" 'kill 12345'
passes "command without kill verbs" 'ls -l'
passes "pgrep without -f" 'pgrep my-service-other'

printf '# empty\n' > "$TMP/empty"
R=$(jq -n --arg c 'pkill -f dist/server' '{tool_input:{command:$c}}' | PROTECTED_PROCESSES_CONF="$TMP/empty" bash "$HOOK" 2>/dev/null; echo $?)
[ "$R" = 0 ] && ok "empty config: guard off" || ko "empty config"
R=$(jq -n --arg c 'pkill -f dist/server' '{tool_input:{command:$c}}' | PROTECTED_PROCESSES_CONF=/does/not/exist bash "$HOOK" 2>/dev/null; echo $?)
[ "$R" = 0 ] && ok "missing config: fail-open" || ko "missing config"
printf 'not json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "fail-open on invalid JSON" || ko "invalid JSON"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
