#!/usr/bin/env bash
# automode-warn.test.sh -- test battery for automode-warn.sh.
# Run: bash .claude/hooks/automode-warn.test.sh   Exit 0 = all pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/automode-warn.sh}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/automode-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export AUTOMODE_MARK_DIR="$TMP/marks"
unset CLAUDE_CODE_ENTRYPOINT
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
run() { jq -n --arg s "$1" --arg m "$2" '{session_id:$s,permission_mode:$m,prompt:"hi"}' | bash "$HOOK"; }

[ -x "$HOOK" ] && ok "hook is executable" || ko "hook is not executable"
run S1 auto | jq -e '.hookSpecificOutput.additionalContext|test("auto mode")' >/dev/null && ok "auto mode warns" || ko "auto mode warns"
[ -z "$(run S1 auto)" ] && ok "second message in the same session: silence" || ko "warned twice"
[ -z "$(run S2 default)" ] && ok "default mode: silence" || ko "default mode"
[ -z "$(run '' auto)" ] && ok "no session id: silence" || ko "no session id"
[ -z "$(jq -n '{session_id:"S3",permission_mode:"auto"}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli bash "$HOOK")" ] && ok "silent in headless" || ko "headless"
printf 'not json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "fail-open on invalid JSON" || ko "invalid JSON"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
