#!/usr/bin/env bash
# commit-nudge.sh -- PostToolUse (Write|Edit|NotebookEdit)
#
# Nudges the agent when it piles up edits in a git repository without a commit.
# First nudge at 25 edits, then every 10 (35, 45, 55...).
# NEVER blocks: exit 0 always, the nudge goes back as additionalContext.
#
# Why it exists: a build agent can run out of turns with a whole feature on disk and not a
# single commit or push, despite a "commit as you go" line in its definition. The work then
# survives only by luck. A written rule does not fire actions; hooks do.
#
# Facts this design relies on:
#   1. PostToolUse hooks DO fire inside subagents, and the feedback reaches the subagent.
#   2. Subagents SHARE the parent's session_id. So the state key cannot be the session id
#      alone, or parallel agents would add up. The key includes the repository top level,
#      which for agents working in separate worktrees separates them naturally.
#
# State: one small file per (session, repo) in COMMIT_NUDGE_STATE_DIR with the HEAD seen
# and the count. A new commit (HEAD changes) resets the count; a clean tree resets it too.
# Test: .claude/hooks/commit-nudge.test.sh
set -u

STATE_DIR="${COMMIT_NUDGE_STATE_DIR:-${TMPDIR:-/tmp}/genesis-commit-nudge}"
THRESHOLD=25   # first nudge
REPEAT=10      # following nudges

INPUT="$(cat 2>/dev/null)" || exit 0
command -v jq >/dev/null 2>&1 || exit 0
file_path="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_response.filePath // empty' 2>/dev/null)"
sid="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
[ -z "${file_path:-}" ] && exit 0

# Walk up to the first directory that exists (a Write may target a new subfolder).
dir="$file_path"
[ -f "$dir" ] && dir="$(dirname "$dir")"
i=0
while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$i" -lt 8 ]; do
  dir="$(dirname "$dir")"; i=$((i+1))
done
[ -d "$dir" ] || exit 0

gitout="$(git -C "$dir" rev-parse --show-toplevel HEAD 2>/dev/null)" || exit 0
top="$(printf '%s' "$gitout" | sed -n '1p')"
head_sha="$(printf '%s' "$gitout" | sed -n '2p')"
[ -n "$top" ] && [ -n "$head_sha" ] || exit 0

key="$(printf '%s|%s' "${sid:-nosid}" "$top" | shasum | cut -c1-16)" || exit 0
[ -n "$key" ] || exit 0
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
state="$STATE_DIR/$key"

prev_head=""; count=0
if [ -r "$state" ]; then
  read -r prev_head count < "$state" 2>/dev/null || { prev_head=""; count=0; }
  case "${count:-}" in (''|*[!0-9]*) count=0 ;; esac
fi
if [ "$prev_head" != "$head_sha" ]; then
  count=0
fi
count=$((count+1))

write_state() {
  printf '%s %s\n' "$head_sha" "$1" > "$state.$$" 2>/dev/null && mv -f "$state.$$" "$state" 2>/dev/null
  find "$STATE_DIR" -type f -mtime +3 -delete 2>/dev/null
}

if [ "$count" -lt "$THRESHOLD" ]; then
  write_state "$count"; exit 0
fi
if [ $(( (count - THRESHOLD) % REPEAT )) -ne 0 ]; then
  write_state "$count"; exit 0
fi
# At a nudge point: only nudge if the tree is actually dirty.
if [ -z "$(git -C "$top" status --porcelain 2>/dev/null | head -n 1)" ]; then
  write_state 0; exit 0
fi
write_state "$count"

repo_label="${top/#$HOME/~}"
msg="COMMIT-NUDGE: $count edits without a commit in $repo_label. Get what is done to green, commit and push now. A commit resets the counter; next nudge at $((count + REPEAT))."
jq -n --arg ctx "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
