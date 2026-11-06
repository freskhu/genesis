#!/usr/bin/env bash
# check.test.sh -- tests for both banlist detectors:
#   .claude/skills/voice-gate/check.sh   hard block, exit 0/1/2
#   .claude/hooks/voice-check.sh         soft alert, additionalContext as JSON
# Run:  bash .claude/skills/voice-gate/check.test.sh
# Every fixture is synthetic, born in a temporary folder and removed by the trap.
# Exit 0 = all cases pass.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
PASS=0; FAIL=0

# Both detectors stay inert until .claude/rules/voice-banlist.md exists, so the test builds
# a throwaway tree with the example banlist in its place.
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
T="$TMP/repo"
mkdir -p "$T/.claude/skills/voice-gate" "$T/.claude/hooks" "$T/.claude/rules" "$T/outbox"
cp "$REPO/.claude/skills/voice-gate/check.sh" "$T/.claude/skills/voice-gate/"
cp "$REPO/.claude/hooks/voice-check.sh" "$T/.claude/hooks/"
cp "$REPO/.claude/rules/voice-banlist.example.md" "$T/.claude/rules/voice-banlist.md"
CHECK="${CHECK:-$T/.claude/skills/voice-gate/check.sh}"
HOOK="${HOOK:-$T/.claude/hooks/voice-check.sh}"
export CLAUDE_PROJECT_DIR="$T"
F="$T/outbox/sample.md"

fixture() { # the front matter fixes the context: the temporary path decides nothing
  printf 'voice-context: corporate\n\n%b\n' "$1" > "$F"
}

gate() { # gate <expected passed|blocked> <name> <text> [<required output snippet>]
  local want="$1" name="$2" text="$3" snippet="${4:-}" out rc got
  fixture "$text"
  out=$(bash "$CHECK" "$F" 2>/dev/null); rc=$?
  case "$rc" in 0) got=passed ;; 1) got=blocked ;; *) got="error:$rc" ;; esac
  if [ "$got" = "$want" ] && { [ -z "$snippet" ] || printf '%s' "$out" | grep -qF "$snippet"; }; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL check.sh [%s]: want %s %s, got %s\n%s\n' "$name" "$want" "$snippet" "$got" "$out"
  fi
}

hook() { # hook <expected silent|warn> <name> <text> [<required output snippet>]
  local want="$1" name="$2" text="$3" snippet="${4:-}" out got
  fixture "$text"
  out=$(jq -n --arg f "$F" '{tool_name:"Write",tool_input:{file_path:$f}}' | env -u CLAUDE_EFFORT bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q additionalContext; then got=warn; else got=silent; fi
  if [ "$got" = "$want" ] && { [ -z "$snippet" ] || printf '%s' "$out" | grep -qF "$snippet"; }; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL voice-check.sh [%s]: want %s %s, got %s\n%s\n' "$name" "$want" "$snippet" "$got" "$out"
  fi
}

both_pass()  { gate passed "$1" "$2"; hook silent "$1" "$2"; }
both_catch() { gate blocked "$1" "$2" "$3"; hook warn "$1" "$2" "$3"; }

URL='https://example.org/leverage/robust-archive/page.html'

# --- a URL is not prose
both_pass "banned word inside a URL"        "Source: $URL"
both_pass "http without s"                  "Source: http://example.org/leverage/1"
both_pass "scheme in capitals"              "Source: HTTPS://EXAMPLE.ORG/LEVERAGE/1"
both_pass "two URLs on one line"            "See $URL and http://example.org/robust/2 for context."
both_pass "markdown link target"            "See [the archive]($URL) for context."
both_pass "autolink"                        "See <$URL> for context."
both_pass "em-dash inside a URL"            "See https://example.org/a—b for context."
both_pass "clean prose"                     "The report is in the shared folder."

# --- prose is still caught
both_catch "inflated word in prose"          "We will leverage the archive."           "T1.E"
both_catch "URL and banned word on one line" "We will leverage $URL today."            "T1.E"
both_catch "banned word right after a URL"   "See $URL to leverage it."                "T1.E"
both_catch "markdown link text"              "See [how to leverage it]($URL) here."    "T1.E"
both_catch "no scheme is not a URL"          "See www.example.org/leverage for context." "T1.E"
both_catch "em-dash in prose next to a URL"  "This — $URL — that."                     "T1.G"

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
