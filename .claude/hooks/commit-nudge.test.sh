#!/usr/bin/env bash
# commit-nudge.test.sh -- test battery for commit-nudge.sh on a throwaway git repository.
# Identity for the test commits goes through `git -c`, never `git config`.
# Run: bash .claude/hooks/commit-nudge.test.sh   Exit 0 = all pass.
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/commit-nudge.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/commitnudge-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export COMMIT_NUDGE_STATE_DIR="$TMP/state"
PASS=0; FAIL=0
G() { git -C "$repo" -c user.email=test@example.invalid -c user.name=Test "$@"; }

repo="$TMP/repo"; mkdir -p "$repo/src"
git -C "$repo" init -q
echo base > "$repo/src/a.txt"
G add -A && G commit -qm base

fire() {
  local sid="$1" fp="$2" tool="${3:-Edit}"
  jq -n --arg s "$sid" --arg t "$tool" --arg f "$fp" \
    '{session_id:$s,hook_event_name:"PostToolUse",tool_name:$t,tool_input:{file_path:$f},tool_response:{filePath:$f}}' \
    | bash "$HOOK" 2>/dev/null
}
dirty() { echo "change $RANDOM" >> "$repo/src/a.txt"; }
check() { # check <name> <want: warn|silent> <output>
  local got=silent
  printf '%s' "$3" | grep -q 'COMMIT-NUDGE' && got=warn
  if [ "$got" = "$2" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 (want=$2 got=$got)"; FAIL=$((FAIL+1)); fi
}
state_count() { local f="$COMMIT_NUDGE_STATE_DIR/$(printf '%s|%s' "$1" "$2" | shasum | cut -c1-16)"; [ -r "$f" ] && awk '{print $2}' "$f" || echo "-"; }
top="$(git -C "$repo" rev-parse --show-toplevel)"

[ -x "$HOOK" ] && { echo "PASS  hook is executable"; PASS=$((PASS+1)); } || { echo "FAIL  hook is not executable"; FAIL=$((FAIL+1)); }

dirty
out=""; for i in $(seq 1 24); do out="$(fire S1 "$repo/src/a.txt")"; done
check "24 edits without commit: silence" silent "$out"
[ "$(state_count S1 "$top")" = 24 ] && { echo "PASS  counter=24"; PASS=$((PASS+1)); } || { echo "FAIL  counter"; FAIL=$((FAIL+1)); }
check "25th edit: nudge" warn "$(fire S1 "$repo/src/a.txt")"
out=""; for i in $(seq 26 34); do out="$(fire S1 "$repo/src/a.txt")"; done
check "edits 26-34: silence" silent "$out"
check "35th edit: nudge (every 10)" warn "$(fire S1 "$repo/src/a.txt")"

G add -A && G commit -qm work; dirty
check "1st edit after a commit: silence" silent "$(fire S1 "$repo/src/a.txt")"
[ "$(state_count S1 "$top")" = 1 ] && { echo "PASS  commit reset the counter"; PASS=$((PASS+1)); } || { echo "FAIL  reset"; FAIL=$((FAIL+1)); }

G add -A; G commit -qm clean
out=""; for i in $(seq 1 25); do out="$(fire S2 "$repo/src/a.txt")"; done
check "25 edits on a clean tree: silence" silent "$out"

mkdir -p "$TMP/notrepo"
out=""; for i in $(seq 1 30); do out="$(fire S3 "$TMP/notrepo/x.md")"; done
check "30 edits outside any repo: silence" silent "$out"

dirty
out=""; for i in $(seq 1 25); do out="$(fire S4 "$repo/src/new/dir/file.ts" Write)"; done
check "25 Writes to a not-yet-existing path in the repo: nudge" warn "$out"

check "no file_path: silence" silent "$(printf '{"session_id":"S1","tool_name":"Edit","tool_input":{}}' | bash "$HOOK" 2>/dev/null)"
printf 'not json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && { echo "PASS  fail-open on invalid JSON"; PASS=$((PASS+1)); } || { echo "FAIL  invalid JSON"; FAIL=$((FAIL+1)); }

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
