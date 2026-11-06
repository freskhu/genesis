#!/usr/bin/env bash
# correction-nudge.test.sh -- test battery for correction-nudge.sh. Uses a temporary log,
# never the real one.
# Run: bash .claude/hooks/correction-nudge.test.sh   Exit 0 = all pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/correction-nudge.sh}"
export CORRECTIONS_SCRIPT="${CORRECTIONS_SCRIPT:-$HERE/../../scripts/corrections.py}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/corrections-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export CORRECTIONS_LOG="$TMP/c.tsv"
unset CLAUDE_CODE_ENTRYPOINT
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
msg() { jq -n --arg s "$1" --arg p "$2" '{session_id:$s,hook_event_name:"UserPromptSubmit",prompt:$p}'; }
run() { msg "$1" "$2" | bash "$HOOK"; }
nudges() { run "$1" "$2" | grep -q additionalContext; }
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

[ -x "$HOOK" ] && ok "hook is executable" || ko "hook is not executable"

nudges A "you made that up" && ko "1st correction does not nudge" || ok "1st correction does not nudge"
nudges A "I already told you it is not like that" && ok "2nd correction in the same session nudges" || ko "2nd correction nudges"
nudges B "how many times do I have to repeat this" && ko "another session does not inherit the counter" || ok "another session does not inherit the counter"
nudges A "you always had access to that" && ok "3rd correction in session A nudges" || ko "3rd correction in session A"
nudges B "you are inventing things again" && ok "2nd in session B nudges, own counter" || ko "2nd in session B"
[ "$(awk -F'\t' '$2=="A"' "$CORRECTIONS_LOG" | wc -l | tr -d ' ')" = 3 ] && ok "counter A = 3" || ko "counter A"
[ "$(awk -F'\t' '$2=="B"' "$CORRECTIONS_LOG" | wc -l | tr -d ' ')" = 2 ] && ok "counter B = 2" || ko "counter B"

BEFORE=$(wc -l < "$CORRECTIONS_LOG")
nudges "" "I already told you" && ko "empty session does not nudge" || ok "empty session does not nudge"
nudges C "good morning, check the report" && ko "normal message does not nudge" || ok "normal message does not nudge"
nudges A "/made-up" && ko "slash command does not nudge" || ok "slash command does not nudge"
nudges A "<task-notification>I already told you</task-notification>" && ko "system message does not nudge" || ok "system message does not nudge"
nudges A "make an inventory of the stock" && ko "inventory is not inventing" || ok "inventory is not inventing"
LONG=$(printf 'paste %.0s' $(seq 1 150))
nudges A "$LONG I already told you" && ko "long paste does not nudge" || ok "long paste does not nudge"
[ "$(wc -l < "$CORRECTIONS_LOG")" = "$BEFORE" ] && ok "none of these reach the log" || ko "something reached the log"

run D "UNIQUEMARKER you made that up" >/dev/null
grep -q UNIQUEMARKER "$CORRECTIONS_LOG" && ko "log stores text" || ok "log does not store text"
[ "$(awk -F'\t' '{print NF}' "$CORRECTIONS_LOG" | sort -u)" = 3 ] && ok "log has exactly 3 fields" || ko "log has other fields"
[ "$(mode_of "$CORRECTIONS_LOG")" = 600 ] && ok "log has mode 600" || ko "log mode"

CLAUDE_CODE_ENTRYPOINT=sdk-cli run A "I already told you" | grep -q . && ko "silent in headless" || ok "silent in headless"
L1=$(wc -l < "$CORRECTIONS_LOG")
CLAUDE_CODE_ENTRYPOINT=sdk-cli run A "I already told you" >/dev/null
[ "$(wc -l < "$CORRECTIONS_LOG")" = "$L1" ] && ok "headless does not log" || ko "headless logs"

printf 'not json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "fail-open on invalid JSON" || ko "invalid JSON"
msg A "I already told you" | CORRECTIONS_SCRIPT=/does/not/exist bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "fail-open without script" || ko "without script"

run A "I already told you" | jq -e '.hookSpecificOutput.hookEventName=="UserPromptSubmit"' >/dev/null && ok "valid JSON output" || ko "JSON output"

M=$(python3 "$CORRECTIONS_SCRIPT" measure --since 2000-01-01)
printf '%s' "$M" | grep -q "second or later" && ok "measure reports the share" || ko "measure"
printf '%s' "$M" | grep -q UNIQUEMARKER && ko "measure prints text" || ok "measure prints no text"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
