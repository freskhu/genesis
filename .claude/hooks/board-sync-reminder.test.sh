#!/usr/bin/env bash
# board-sync-reminder.test.sh -- smoke test for board-sync-reminder.sh (unconfigured state).
# Run: bash .claude/hooks/board-sync-reminder.test.sh   Exit 0 = all pass.
. "$(cd "$(dirname "$0")" && pwd)/smoke-tests.lib.sh"
H="$HOOKS_DIR/board-sync-reminder.sh"
unset BOARD_REPO
[ -x "$H" ] && ok "hook is executable" || ko "hook is not executable"
expect_rc "no board configured: silent on gh pr merge" 0 "$H" '{"tool_input":{"command":"gh pr merge 12 --squash"}}'
expect_rc "no board configured: silent on any command" 0 "$H" '{"tool_input":{"command":"ls"}}'
[ ! -s "$SMOKE_TMP/out" ] && ok "no output when unconfigured" || ko "printed output when unconfigured"
expect_rc "invalid JSON: fail-open" 0 "$H" 'not json'
smoke_done
