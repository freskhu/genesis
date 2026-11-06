#!/usr/bin/env bash
# prod-kill-guard.sh -- PreToolUse (Bash): blocks pattern-based process killing that can
# reach a production service.
#
# Why it exists: a test copy of a service often runs the SAME executable as production
# (`node dist/server/index.js`, `python app.py`). No command-line pattern can tell the two
# apart, so `pkill -f <pattern>` stops the production process too. The only safe way to
# stop your own process is by the PID its own start saved.
#
# BLOCKS (exit 2):
#   1. pkill / killall whose pattern or name matches a protected pattern
#      (with or without -f: `pkill node` hits production by name).
#   2. pgrep -f of a protected pattern on a line that ALSO has `kill`
#      (kill $(pgrep -f ...), pgrep -f ... | xargs kill).
# WARNS, without blocking (additionalContext):
#   3. pgrep -f of a protected pattern without kill on the same line. Reading is fine; the
#      warning exists because the next step is usually the kill.
#
# Protected patterns: one extended regex per line in .claude/hooks/protected-processes.conf
# (override with PROTECTED_PROCESSES_CONF). Empty file = the hook does nothing.
# Test: .claude/hooks/prod-kill-guard.test.sh
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0
case "$COMMAND" in
  *pkill*|*killall*|*pgrep*) ;;
  *) exit 0 ;;
esac

CONF="${PROTECTED_PROCESSES_CONF:-$(cd "$(dirname "$0")" && pwd)/protected-processes.conf}"
[ -r "$CONF" ] || exit 0
PROTECT_RE=$(grep -vE '^[[:space:]]*(#|$)' "$CONF" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | paste -sd'|' -)
[ -z "$PROTECT_RE" ] && exit 0

EFFORT="${CLAUDE_EFFORT:-$(echo "$INPUT" | jq -r '.effort.level // empty' 2>/dev/null || true)}"
EFFORT="${EFFORT:-n/a}"

word_re() { printf '(^|[^a-zA-Z0-9_./-])%s([^a-zA-Z0-9_-]|$)' "$1"; }
args_of() { # args_of <segment> <verb>
  printf '%s' "$1" | sed -E "s/^.*$2//" | sed -E 's/\|.*$//'
}

BLOCK_MSG=""
WARN_MSG=""
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  for VERB in pkill killall; do
    if echo "$SEG" | grep -qE "$(word_re "$VERB")"; then
      PAT=$(args_of "$SEG" "$VERB")
      if echo "$PAT" | grep -qiE "$PROTECT_RE"; then
        BLOCK_MSG="$VERB with a pattern that matches a protected process:$PAT"
        break 2
      fi
    fi
  done
  if echo "$SEG" | grep -qE "$(word_re pgrep)"; then
    PARGS=$(args_of "$SEG" pgrep)
    if echo "$PARGS" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*f|--full)([[:space:]=]|$)' \
       && echo "$PARGS" | grep -qiE "$PROTECT_RE"; then
      if echo "$SEG" | grep -qE "$(word_re kill)"; then
        BLOCK_MSG="pgrep -f feeding kill, with a pattern that matches a protected process:$PARGS"
        break
      else
        WARN_MSG="$PARGS"
      fi
    fi
  fi
done <<EOF
$(printf '%s' "$COMMAND" | sed -E 's/(&&|\|\||;)/\n/g')
EOF

if [ -n "$BLOCK_MSG" ]; then
  cat >&2 <<MSG
BLOCKED [effort=$EFFORT]: $BLOCK_MSG
Killing by pattern cannot tell your test copy from the production process: both run the
same executable.
Stop by PID, saved to a file by the start itself:
  <command> & echo \$! > "\$TMPDIR/my-test.pid"     # on start
  kill "\$(cat "\$TMPDIR/my-test.pid")"             # on stop
If the process is not yours (production, an always-on session), do not stop it here: hand
it to whoever owns the service manager entry.
Looking without killing passes: pgrep -f <pattern> alone, with no kill on the same line.
MSG
  exit 2
fi

if [ -n "$WARN_MSG" ]; then
  REASON="prod-kill-guard: pgrep -f of a pattern that matches a protected process ($(printf '%s' "$WARN_MSG" | tr -d '"' | cut -c1-80)). Reading is fine. If the next step is a kill, do not use this pattern: stop by the PID saved in a file, or through the service manager if the process is production."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' \
    "$(printf '%s' "$REASON" | jq -Rs .)"
fi
exit 0
