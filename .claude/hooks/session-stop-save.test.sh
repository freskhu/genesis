#!/usr/bin/env bash
# session-stop-save.test.sh -- test battery for the message count in session-stop-save.sh.
# Copies the hook into a temporary tree with a fake generate_memory_hot.py: never touches
# the real briefing.
# Run: bash .claude/hooks/session-stop-save.test.sh   Exit 0 = all pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ORIG="${HOOK:-$HERE/session-stop-save.sh}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/stopsave-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude/hooks" "$TMP/scripts" "$TMP/home"
cp "$ORIG" "$TMP/.claude/hooks/session-stop-save.sh"
printf 'import sys\nsys.exit(0)\n' > "$TMP/scripts/generate_memory_hot.py"
HOOK="$TMP/.claude/hooks/session-stop-save.sh"; chmod +x "$HOOK"
export HOME="$TMP/home"
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
[ -x "$ORIG" ] && ok "hook is executable" || ko "hook is not executable"

python3 - "$TMP" <<'PY'
import json,sys
t=sys.argv[1]
def u(c,**k): return json.dumps({"type":"user","message":{"role":"user","content":c},**k})
def res(): return u([{"type":"tool_result","tool_use_id":"x","content":"output"}])
def w(n,l): open(f"{t}/{n}.jsonl","w").write("\n".join(l)+"\n")
w("t14",[u("message")]*14+[res()]*200)
w("t15",[u([{"type":"text","text":"message"}])]*15)
w("cmd",[u("<command-message>x</command-message>")]*40)
w("meta",[u("text",isMeta=True)]*40+[u("<system-reminder>x</system-reminder>")]*40+[u("<task-notification>x</task-notification>")]*40+[u("<bash-stdout>x</bash-stdout>")]*40+[u("summary",isCompactSummary=True)]*40)
w("empty",[u("   ")]*40+[u([{"type":"text","text":""}])]*40)
w("mixed",[u("message")]*10+[res()]*50+[u([{"type":"tool_result","tool_use_id":"x","content":"s"},{"type":"text","text":"message"}])]*5)
PY
run() { jq -n --arg s "$1" --arg t "$TMP/$2.jsonl" '{session_id:$s,transcript_path:$t}' | "$HOOK" 2>/dev/null; }
blocks() { run "$1" "$2" | grep -q '"decision"'; }

blocks s1 t14 && ko "14 typed messages with 200 tool results do not block" || ok "14 typed messages with 200 tool results do not block"
blocks s2 t15 && ok "15 typed messages block" || ko "15 typed messages block"
blocks s2 t15 && ko "no new messages: second Stop exits clean" || ok "no new messages: second Stop exits clean"
blocks s3 cmd && ko "<command-message> stays excluded" || ok "<command-message> stays excluded"
blocks s4 meta && ko "harness-injected text does not count" || ok "harness-injected text does not count"
blocks s5 empty && ko "empty text does not count" || ok "empty text does not count"
blocks s6 mixed && ok "tool result with text counts: 15 in the mixed transcript" || ko "mixed"

# Session with a mark from an older counting rule: must not stay silent until it catches up.
mkdir -p "$HOME/.mempalace/hook_state"; echo 900 > "$HOME/.mempalace/hook_state/s7_last_save"
blocks s7 t15 && ko "old mark above the count: no block on this pass" || ok "old mark above the count: no block on this pass"
[ "$(cat "$HOME/.mempalace/hook_state/s7_last_save")" = 15 ] && ok "old mark realigned to the count" || ko "mark not realigned"

R=$(jq -n --arg t "$TMP/t15.jsonl" '{session_id:"s8",transcript_path:$t,stop_hook_active:true}' | "$HOOK"); [ "$R" = "{}" ] && ok "stop_hook_active exits clean" || ko "stop_hook_active"
R=$(jq -n --arg t "$TMP/subagents/agent-a.jsonl" '{session_id:"s9",transcript_path:$t}' | "$HOOK"); [ "$R" = "{}" ] && ok "subagent exits clean" || ko "subagent"
R=$(run s10 missing); [ "$R" = "{}" ] && ok "missing transcript exits clean" || ko "missing transcript"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
