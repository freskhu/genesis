#!/usr/bin/env bash
# sql-guardrails.sh -- Blocks destructive SQL via sqlite3
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0

case "$COMMAND" in
  *sqlite3*)
    # Block DROP TABLE/VIEW (use migrations instead)
    if echo "$COMMAND" | grep -iqE '\bDROP\s+(TABLE|VIEW)\b'; then
      echo "BLOCKED: DROP TABLE/VIEW detected. Use migrations instead." >&2
      exit 2
    fi
    # Block DELETE without WHERE clause
    if echo "$COMMAND" | grep -iqE '\bDELETE\b' && ! echo "$COMMAND" | grep -iqE '\bWHERE\b'; then
      echo "BLOCKED: DELETE without WHERE clause detected." >&2
      exit 2
    fi
    # Block TRUNCATE
    if echo "$COMMAND" | grep -iqE '\bTRUNCATE\b'; then
      echo "BLOCKED: TRUNCATE detected." >&2
      exit 2
    fi
    ;;
esac
exit 0
