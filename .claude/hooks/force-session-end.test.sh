#!/usr/bin/env bash
# force-session-end.test.sh -- smoke test for force-session-end.sh (fail-open paths).
# Run: bash .claude/hooks/force-session-end.test.sh   Exit 0 = all pass.
. "$(cd "$(dirname "$0")" && pwd)/smoke-tests.lib.sh"
[ -x "$HOOKS_DIR/force-session-end.sh" ] && ok "hook is executable" || ko "hook is not executable"
H=$(copy_tree force-session-end.sh)
expect_rc "stop_hook_active: lets Stop through" 0 "$H" '{"session_id":"s","stop_hook_active":true}'
expect_rc "subagent transcript: lets Stop through" 0 "$H" '{"session_id":"s","transcript_path":"/x/subagents/agent-a.jsonl"}'
expect_rc "missing transcript on an empty DB: no crash" 0 "$H" '{"session_id":"s","transcript_path":"/does/not/exist.jsonl"}'
rm -f "$(dirname "$H")/../../Database/team.db"
expect_rc "missing DB: fail-open" 0 "$H" '{"session_id":"s"}'
smoke_done
