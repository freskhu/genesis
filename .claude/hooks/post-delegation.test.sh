#!/usr/bin/env bash
# post-delegation.test.sh -- smoke test for post-delegation.sh.
# Run: bash .claude/hooks/post-delegation.test.sh   Exit 0 = all pass.
. "$(cd "$(dirname "$0")" && pwd)/smoke-tests.lib.sh"
[ -x "$HOOKS_DIR/post-delegation.sh" ] && ok "hook is executable" || ko "hook is not executable"
H=$(copy_tree post-delegation.sh)
expect_rc "another tool: out of scope" 0 "$H" '{"tool_name":"Bash"}'
expect_rc "Task with no diary or activity row: blocks" 2 "$H" '{"tool_name":"Task"}'
DB="$(dirname "$H")/../../Database/team.db"
sqlite3 "$DB" "INSERT INTO diary_entries (agent_name, content) VALUES ('a','reflection');"
expect_rc "Task with a fresh diary row: passes" 0 "$H" '{"tool_name":"Task"}'
rm -f "$DB"
expect_rc "missing DB: fail-open" 0 "$H" '{"tool_name":"Task"}'
smoke_done
