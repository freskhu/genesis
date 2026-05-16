#!/usr/bin/env bash
# block-temp-inbox.sh -- Blocks Write/Edit of temp files to Owners Inbox/
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  *"Owners Inbox/"*)
    BASENAME=$(basename "$FILE_PATH")
    case "$BASENAME" in
      '~$'*|*.tmp|.DS_Store)
        echo "BLOCKED: Temp file '$BASENAME' cannot be written to Owners Inbox/" >&2
        exit 2
        ;;
    esac
    ;;
esac
exit 0
