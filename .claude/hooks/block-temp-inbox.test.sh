#!/usr/bin/env bash
# block-temp-inbox.test.sh -- smoke test for block-temp-inbox.sh.
# Run: bash .claude/hooks/block-temp-inbox.test.sh   Exit 0 = all pass.
. "$(cd "$(dirname "$0")" && pwd)/smoke-tests.lib.sh"
H="$HOOKS_DIR/block-temp-inbox.sh"
[ -x "$H" ] && ok "hook is executable" || ko "hook is not executable"
expect_rc "Office lock file in outbox blocks" 2 "$H" '{"tool_input":{"file_path":"/p/outbox/~$report.docx"}}'
expect_rc ".tmp file in outbox blocks" 2 "$H" '{"tool_input":{"file_path":"/p/outbox/x.tmp"}}'
expect_rc "relative outbox path blocks" 2 "$H" '{"tool_input":{"file_path":"outbox/x.tmp"}}'
expect_rc "folder that only ends in outbox passes" 0 "$H" '{"tool_input":{"file_path":"/p/myoutbox/x.tmp"}}'
expect_rc "normal deliverable passes" 0 "$H" '{"tool_input":{"file_path":"/p/outbox/report.md"}}'
expect_rc "temp file elsewhere passes" 0 "$H" '{"tool_input":{"file_path":"/p/scratch/x.tmp"}}'
expect_rc "no file_path passes" 0 "$H" '{"tool_input":{}}'
smoke_done
