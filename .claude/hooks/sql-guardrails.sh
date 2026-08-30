#!/usr/bin/env bash
# sql-guardrails.sh -- Blocks destructive SQL via sqlite3
#
# Scope: blocks DROP TABLE/VIEW, DELETE-without-WHERE, and TRUNCATE against
# REAL schema objects only. Two false positives are deliberately excluded:
#   1. Temporary objects (temp.* / TEMP TABLE) -- safe teardown pattern.
#   2. Trigger phrases that appear inside quoted string literals (e.g. the
#      text "DROP TABLE" embedded in a JSON evidence payload) -- not SQL.
# Real destructive statements against persistent tables/views STILL block.
# Fail-safe: on any parsing uncertainty the original command is preserved
# and, where a real destructive verb is seen, the block still fires.
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0

# Effort context — env var first, JSON stdin (.effort.level) fallback,
# n/a when the model does not support effort. TELEMETRY ONLY: a safety hook never
# relaxes a block based on effort (you never allow a DROP TABLE just because the
# effort is high). Surfaced in the block message so a fired block carries the
# effort context. Values: low|medium|high|xhigh|max.
EFFORT="${CLAUDE_EFFORT:-$(echo "$INPUT" | jq -r '.effort.level // empty' 2>/dev/null || true)}"
EFFORT="${EFFORT:-n/a}"

case "$COMMAND" in
  *sqlite3*)
    # Strip SQL string literals before pattern matching so trigger phrases
    # carried INSIDE data (e.g. a JSON evidence payload) do not register as
    # SQL statements. SQLite string literals are SINGLE-quoted; double quotes
    # are the shell delimiter around the sqlite3 SQL argument, so stripping
    # them would erase the real query -- only single-quoted literals are
    # stripped. This only affects detection; the original $COMMAND is never
    # modified or re-emitted (fail-safe).
    STRIPPED=$(printf '%s' "$COMMAND" | sed -E "s/'[^']*'//g")

    # Block DROP TABLE/VIEW (use migrations instead), but allow temp objects:
    # DROP [TEMP|TEMPORARY] TABLE/VIEW [IF EXISTS] temp.<name>  -> safe teardown.
    if echo "$STRIPPED" | grep -iqE '\bDROP\s+(TABLE|VIEW)\b'; then
      if echo "$STRIPPED" | grep -iqE '\bDROP\s+(TEMP|TEMPORARY)\s+(TABLE|VIEW)\b' \
         || echo "$STRIPPED" | grep -iqE '\bDROP\s+(TABLE|VIEW)\s+(IF\s+EXISTS\s+)?temp\.'; then
        : # temporary object teardown -- allowed
      else
        echo "BLOCKED [effort=$EFFORT]: DROP TABLE/VIEW detected. Use migrations instead." >&2
        exit 2
      fi
    fi
    # Block DELETE without WHERE clause (real tables only -- string-stripped)
    if echo "$STRIPPED" | grep -iqE '\bDELETE\b' && ! echo "$STRIPPED" | grep -iqE '\bWHERE\b'; then
      echo "BLOCKED [effort=$EFFORT]: DELETE without WHERE clause detected." >&2
      exit 2
    fi
    # Block TRUNCATE (string-stripped)
    if echo "$STRIPPED" | grep -iqE '\bTRUNCATE\b'; then
      echo "BLOCKED [effort=$EFFORT]: TRUNCATE detected." >&2
      exit 2
    fi
    ;;
esac
exit 0
