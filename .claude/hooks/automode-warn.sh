#!/usr/bin/env bash
# automode-warn.sh -- UserPromptSubmit: warns once per session that it runs in auto mode.
#
# Why it exists: in auto mode the permission classifier refuses some real-world writes
# (sending email, writing to a network share or a business system) that in normal mode go
# through the project permissions. The owner found out halfway through a task. A warning in
# the first answer lets them switch mode (Shift+Tab) before the work starts.
#
# UserPromptSubmit receives `permission_mode` in its stdin JSON; SessionStart does not,
# which is why this runs on the first message instead of at session start.
#
# Contract: never blocks (exit 0 always), fail-open on any error. Once per session_id
# (marker file in AUTOMODE_MARK_DIR). Silent in headless runs.
# Test: .claude/hooks/automode-warn.test.sh

MARK_DIR="${AUTOMODE_MARK_DIR:-${TMPDIR:-/tmp}/genesis-automode-warned}"

[ "${CLAUDE_CODE_ENTRYPOINT:-cli}" = "sdk-cli" ] && { cat >/dev/null; exit 0; }

INPUT="$(cat 2>/dev/null)" || exit 0
PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json,sys,re
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid=re.sub(r"[^A-Za-z0-9_-]","",str(d.get("session_id","")))
print(d.get("permission_mode",""), sid)
' 2>/dev/null)" || exit 0

MODE="${PARSED%% *}"
SID="${PARSED#* }"
[ "$MODE" = "auto" ] || exit 0
[ -n "$SID" ] || exit 0

mkdir -p "$MARK_DIR" 2>/dev/null || exit 0
[ -e "$MARK_DIR/$SID" ] && exit 0
touch "$MARK_DIR/$SID" 2>/dev/null
find "$MARK_DIR" -type f -mtime +3 -delete 2>/dev/null

cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Session in auto mode: the classifier will refuse some real-world writes (email sends, writes to shared drives or business systems). Tell the owner in your first answer, so they can switch mode with Shift+Tab before the work starts."}}
EOF
exit 0
