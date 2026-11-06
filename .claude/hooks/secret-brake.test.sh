#!/usr/bin/env bash
# secret-brake.test.sh -- test battery for secret-brake.sh. Test tokens are fake and are
# assembled at run time, so this file itself carries no secret-shaped string.
# Run: bash .claude/hooks/secret-brake.test.sh   Exit 0 = all pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/secret-brake.sh}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/brake-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CODE_ENTRYPOINT
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
rep() { python3 -c 'import sys; print(sys.argv[1]*int(sys.argv[2]),end="")' "$1" "$2"; }
run() { jq -n --arg p "$1" '{session_id:"T",hook_event_name:"UserPromptSubmit",prompt:$p}' | bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; echo $?; }
stops() { [ "$(run "$2")" = 2 ] && ok "stops: $1" || ko "stops: $1"; }
lets() { [ "$(run "$2")" = 0 ] && [ ! -s "$TMP/out" ] && ok "lets through: $1" || ko "lets through: $1"; }

[ -x "$HOOK" ] && ok "hook is executable" || ko "hook is not executable"

A40=$(rep a 40); H40=$(rep f 40); H64=$(rep a 64)
stops "Anthropic key" "here it is sk-""ant-api03-$A40"
stops "generic sk- key" "sk-""proj-$A40"
stops "GitHub token" "take gh""p_$A40"
stops "GitHub fine-grained token" "github""_p""at_$A40"
stops "Slack token" "xox""b-123456789-abcdefghijkl"
stops "JWT" "eyJ""abcdefghijklmn.eyJ""abcdefghijklmn.abcdefghij"
stops "Google client secret" "GOCSPX-abcdefghijklmnopqrst"
stops "labelled private key" "my private key: 0x$H64"
stops "labelled password" "pass""word: abcdefgh"
stops "password with equals" "pass""word=abcdefgh"

run "MARKER sk-""ant-api03-$A40 MARKER" >/dev/null
grep -q "$A40" "$TMP/out" "$TMP/err" && ko "output echoes the token" || ok "output does not echo the token"
grep -q MARKER "$TMP/out" "$TMP/err" && ko "output echoes the message" || ok "output does not echo the message"
grep -q 'scripts/bin/ait-segredo' "$TMP/err" && ok "points to the secrets channel" || ko "no pointer to the secrets channel"
grep -q '`pass:`' "$TMP/err" && ok "explains how to let a false positive through" || ko "no pass: hint"
[ "$(find "$HOME" -type f | wc -l | tr -d ' ')" = 0 ] && ok "writes no file" || ko "wrote a file"

lets "normal message" "look at yesterday's report"
lets "40-hex commit" "commit $H40 fixed it"
lets "short commit" "see f0532d5"
lets "UUID" "session 8ec6e39b-60fa-455e-bc15-2bfd8432be09"
lets "unlabelled 64-hex hash" "transaction 0x$H64"
lets "variable name" "the API_TOKEN lives in .env"
lets "password mentioned without value" "the portal password is missing"
lets "short key" "sk-abc"
lets "test result" "PASS=75 FAIL=0"

lets "pass: prefix" "pass: pass""word: abcdefgh"
lets "pass: with capitals and space" "  Pass: pass""word: abcdefgh"
stops "pass: in the middle does not count" "look pass: pass""word: abcdefgh"

R=$(jq -n --arg p "pass""word: abcdefgh" '{prompt:$p}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli bash "$HOOK" 2>/dev/null; echo $?); [ "$R" = 0 ] && ok "silent in headless" || ko "headless"
printf 'not json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "fail-open on invalid JSON" || ko "invalid JSON"
printf '' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "fail-open on empty stdin" || ko "empty stdin"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
