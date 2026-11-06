#!/usr/bin/env bash
# precompact-save.test.sh -- smoke test for precompact-save.sh, with a fake briefing script.
# Run: bash .claude/hooks/precompact-save.test.sh   Exit 0 = all pass.
. "$(cd "$(dirname "$0")" && pwd)/smoke-tests.lib.sh"
[ -x "$HOOKS_DIR/precompact-save.sh" ] && ok "hook is executable" || ko "hook is not executable"
H=$(copy_tree precompact-save.sh)
expect_rc "runs and exits 0" 0 "$H" '{"session_id":"s"}'
jq -e '.decision=="block"' "$SMOKE_TMP/out" >/dev/null && ok "asks to save before compaction" || ko "no save request"
grep -q 'financial-data-boundary' "$SMOKE_TMP/out" && ok "reminds the data boundaries" || ko "no boundary reminder"
printf 'import sys\nsys.exit(3)\n' > "$(dirname "$H")/../../scripts/generate_memory_hot.py"
expect_rc "briefing failure: still exits 0" 0 "$H" '{"session_id":"s"}'
grep -q 'FAILED' "$SMOKE_TMP/out" && ok "briefing failure is loud" || ko "briefing failure silent"
smoke_done
