#!/bin/bash
# precompact-save.sh — Save everything before context compaction.
# Replaces the MemPalace precompact hook.

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Regenerate memory-hot.md before compaction
cd "$SCRIPT_DIR" && python3 scripts/generate_memory_hot.py &>/dev/null

echo '{"decision": "block", "reason": "COMPACTION IMMINENT. Save ALL important context from this session to team.db using: python3 scripts/palace.py add --wing team --room decisions --hall hall_facts --content \"...\". Save decisions, findings, and task progress. Run: python3 scripts/generate_memory_hot.py after saving. Continue after saving."}'
