#!/bin/bash
# session-stop-save.sh — Auto-save checkpoint using team.db (sqlite-vec)
# Triggers every 15 messages typed by the owner.
# Test: .claude/hooks/session-stop-save.test.sh
# Regenerates memory-hot.md so next session has fresh context.

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Read stdin (Claude Code hook JSON)
INPUT=$(cat)

# Subagent guard: Stop hooks also fire for subagent sessions (Task tool), where
# every tool result counts as a role=user message — the 15-message threshold is
# hit almost immediately and the block displaces the subagent's final report
# (the "relay truncation" pattern). The session-end/checkpoint protocol belongs
# to the orchestrator's main session only.
SUBAGENT_TP=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
case "$SUBAGENT_TP" in
    */subagents/agent-*)
        echo '{}'
        exit 0
        ;;
esac

# Check if stop hook is already active (prevent infinite loop)
STOP_ACTIVE=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stop_hook_active','false'))" 2>/dev/null)
if [ "$STOP_ACTIVE" = "true" ] || [ "$STOP_ACTIVE" = "True" ]; then
    echo '{}'
    exit 0
fi

# Count human messages from transcript
TRANSCRIPT=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('transcript_path',''))" 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id','unknown'))" 2>/dev/null)

EXCHANGE_COUNT=0
if [ -f "$TRANSCRIPT" ]; then
    EXCHANGE_COUNT=$(python3 -c "
import json, sys
# Only messages the owner typed count. Tool results also arrive as role=user, and so do
# texts injected by the harness (system reminders, task notifications, bash echoes,
# compaction summaries); counting them made the hook fire every few turns.
INJECTED = ('<system-reminder', '<task-notification', '<local-command', '<bash-input', '<bash-stdout', '<bash-stderr')
count = 0
with open('$TRANSCRIPT', errors='replace') as f:
    for line in f:
        try:
            entry = json.loads(line)
            msg = entry.get('message', {})
            if isinstance(msg, dict) and msg.get('role') == 'user':
                content = msg.get('content', '')
                text = content if isinstance(content, str) else ' '.join(b.get('text','') for b in content if isinstance(b, dict) and b.get('type') == 'text')
                if not text.strip() or '<command-message>' in text:
                    continue
                if entry.get('isMeta') or entry.get('isCompactSummary'):
                    continue
                if text.lstrip().startswith(INJECTED):
                    continue
                count += 1
        except: pass
print(count)
" 2>/dev/null)
fi

# Track last save point
STATE_DIR="$HOME/.mempalace/hook_state"
mkdir -p "$STATE_DIR"
LAST_SAVE_FILE="$STATE_DIR/${SESSION_ID}_last_save"
LAST_SAVE=0
if [ -f "$LAST_SAVE_FILE" ]; then
    LAST_SAVE=$(cat "$LAST_SAVE_FILE" 2>/dev/null || echo 0)
fi

# A mark above the current count (left by an older counting rule, or a reused session id)
# would keep the hook silent until the count caught up. Realign it instead.
if [ "$LAST_SAVE" -gt "$EXCHANGE_COUNT" ] 2>/dev/null; then
    LAST_SAVE=$EXCHANGE_COUNT
    echo "$LAST_SAVE" > "$LAST_SAVE_FILE"
fi

SINCE_LAST=$((EXCHANGE_COUNT - LAST_SAVE))

# Save every 15 messages
if [ "$SINCE_LAST" -ge 15 ] && [ "$EXCHANGE_COUNT" -gt 0 ]; then
    echo "$EXCHANGE_COUNT" > "$LAST_SAVE_FILE"

    # Regenerate memory-hot.md in the FOREGROUND and capture failures. A silent
    # regen failure is how broken palace deps go unnoticed for days: the old
    # background "&>/dev/null &" threw the error away. Persistence steps must
    # fail LOUD, unlike safety gates, which fail open.
    REGEN_ERR=$(cd "$SCRIPT_DIR" && python3 scripts/generate_memory_hot.py 2>&1 >/dev/null)
    REGEN_RC=$?
    BASE_REASON='AUTO-SAVE checkpoint. Save key topics and decisions from this session to team.db using: python3 scripts/palace.py add --wing ai_team --room decisions --hall hall_facts --content "...". Then run: python3 scripts/generate_memory_hot.py. Continue after saving. No company financial figures and no health data: save the decision and the path of the file that holds the numbers (.claude/rules/financial-data-boundary.md, .claude/rules/health-data-boundary.md).'
    if [ "$REGEN_RC" -ne 0 ]; then
        WARN="WARNING: generate_memory_hot.py FAILED (rc=$REGEN_RC: $(echo "$REGEN_ERR" | tail -1 | head -c 200)). Memory writes may be down - check the Python deps in requirements.txt BEFORE continuing. "
    else
        WARN=""
    fi
    REASON="$WARN$BASE_REASON" python3 -c "import json,os; print(json.dumps({'decision':'block','reason':os.environ['REASON']}))"
else
    echo '{}'
fi
