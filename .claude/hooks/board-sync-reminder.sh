#!/usr/bin/env bash
# board-sync-reminder.sh — PostToolUse (matcher: Bash)
#
# Reminds the orchestrator to sync the GitHub Project board whenever a Bash
# command actually changes the state of issues or PRs in the tracked repo.
#
# Why a hook and not a rule: the rule already existed in memory, written down,
# and the board still drifted — cards left in Backlog while the work was live,
# issues never added at all. Memory does not fire actions. Hooks do. If a
# behaviour must happen every time an event happens, it belongs in a hook.
#
# Nothing destructive is blocked here: the command has already run (PostToolUse).
# The exit 2 returns the reminder to the model as feedback, the same pattern
# post-delegation.sh uses. Everything else exits 0 in silence.
#
# CONFIGURE (or leave unset and the hook stays inert):
#   BOARD_REPO      — repo slug or fragment to match, e.g. "acme/platform"
#   BOARD_URL       — human-readable board URL, shown in the reminder
#   BOARD_PROJECT_ID / BOARD_FIELD_ID — ids for `gh project item-edit`
# Set them in .claude/settings.json under "env", or export them in your shell.

set -u

BOARD_REPO="${BOARD_REPO:-}"
BOARD_URL="${BOARD_URL:-<your project board URL>}"
BOARD_PROJECT_ID="${BOARD_PROJECT_ID:-<project-id>}"
BOARD_FIELD_ID="${BOARD_FIELD_ID:-<status-field-id>}"

# Not configured -> nothing to remind about.
[ -z "$BOARD_REPO" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

[ -z "$CMD" ] && exit 0

# Only the tracked repo matters (the board belongs to that repo).
case "$CMD" in
  *"$BOARD_REPO"*) : ;;
  *) exit 0 ;;
esac

# Never fire on the board operations themselves (those are the fix, not the
# cause), nor on memory/logging commands that merely MENTION these patterns in
# their text payload (palace.py add, diary-write, sqlite3, doc echo/cat).
case "$CMD" in
  *"project item-"*|*"project field-list"*|*"project view"*) exit 0 ;;
  *"palace.py"*|*"diary-write"*|*"sqlite3"*|*"generate_memory_hot"*) exit 0 ;;
esac

remind() {
  echo "BOARD: $1" >&2
  echo "Board: $BOARD_URL — gh project item-edit --project-id $BOARD_PROJECT_ID --field-id $BOARD_FIELD_ID ; verify with \`gh project item-list\` after moving anything." >&2
  exit 2
}

# The patterns require a real gh invocation, not a mention in prose.
case "$CMD" in
  *"gh pr merge"*)
    remind "you merged a PR. Move the card(s) for the closed issue(s) to the staging column now (or to the production column if you are promoting straight after)."
    ;;
  *"gh api"*"refs/heads/prod"*)
    remind "you promoted to production. Once the deploy is green and you have checked the app, move the cards for the included issues to the production column."
    ;;
  *"gh issue create"*)
    remind "you created an issue. Add the card to the board (item-add plus a column, normally Backlog)."
    ;;
  *"gh issue close"*|*"gh issue reopen"*)
    remind "you changed an issue's state. Confirm the card sits in the right column."
    ;;
esac

exit 0
