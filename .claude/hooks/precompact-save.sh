#!/bin/bash
# precompact-save.sh — Save everything before context compaction.
# Replaces the MemPalace precompact hook.

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Regenerate memory-hot.md before compaction, capturing failures. A silent
# regen failure is how broken palace deps go unnoticed for days.
# Persistence steps must fail LOUD.
REGEN_ERR=$(cd "$SCRIPT_DIR" && python3 scripts/generate_memory_hot.py 2>&1 >/dev/null)
REGEN_RC=$?
BASE_REASON='COMPACTION IMMINENT. Save ALL important context from this session to team.db using: python3 scripts/palace.py add --wing ... --room ... --hall ... --content "...". Save decisions, findings, and task progress. Run: python3 scripts/generate_memory_hot.py after saving. Continue after saving.'
if [ "$REGEN_RC" -ne 0 ]; then
    WARN="WARNING: generate_memory_hot.py FAILED (rc=$REGEN_RC: $(echo "$REGEN_ERR" | tail -1 | head -c 200)). Memory writes may be down - check the Python deps in requirements.txt BEFORE continuing. "
else
    WARN=""
fi
REASON="$WARN$BASE_REASON" python3 -c "import json,os; print(json.dumps({'decision':'block','reason':os.environ['REASON']}))"
