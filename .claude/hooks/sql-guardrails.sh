#!/usr/bin/env bash
# sql-guardrails.sh -- PreToolUse (Bash): blocks destructive SQL sent through sqlite3.
#
# Scope: blocks DROP TABLE/VIEW, DELETE without WHERE, TRUNCATE against a table, and
# direct writes or DDL on spec_criteria, against REAL schema objects only. Three false
# positives are deliberately excluded:
#   1. Temporary objects (temp.* / TEMP TABLE): safe teardown.
#   2. Trigger phrases inside quoted string literals (e.g. "DROP TABLE" inside a JSON
#      evidence payload): data, not SQL.
#   3. PRAGMA wal_checkpoint(TRUNCATE), and the word TRUNCATE in prose or a comment. Only
#      TRUNCATE in statement position (start of line, or right after ; or a quote), followed
#      by an optional TABLE and an identifier, blocks.
#
# Both forms are checked: the raw command AND the command with single-quoted literals
# stripped. Checking only the stripped form missed the idiomatic way of passing SQL to the
# CLI (single quotes): the same statement blocked with double quotes and passed with single.
#
# This is a guard against mistakes, not a security boundary: a python3 script that builds
# the SQL by concatenation goes around it. The defence in the data is the triggers of the
# migrations (e.g. Database/migrations/027_spec_criteria.sql).
#
# Fail-safe: detection only; the original command is never modified or re-emitted.
# Effort is surfaced in the message as telemetry only; it never relaxes a block.
# Test: .claude/hooks/sql-guardrails.test.sh
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0

EFFORT="${CLAUDE_EFFORT:-$(echo "$INPUT" | jq -r '.effort.level // empty' 2>/dev/null || true)}"
EFFORT="${EFFORT:-n/a}"

case "$COMMAND" in
  *sqlite3*)
    # SQLite string literals are single-quoted; double quotes are usually the shell
    # delimiter around the SQL argument, so only single-quoted literals are stripped.
    STRIPPED=$(printf '%s' "$COMMAND" | sed -E "s/'[^']*'//g")

    # DROP TABLE/VIEW: use a migration instead. Temporary objects are allowed.
    if echo "$COMMAND" | grep -iqE '\bDROP\s+(TABLE|VIEW)\b' \
       || echo "$STRIPPED" | grep -iqE '\bDROP\s+(TABLE|VIEW)\b'; then
      if echo "$STRIPPED" | grep -iqE '\bDROP\s+(TEMP|TEMPORARY)\s+(TABLE|VIEW)\b' \
         || echo "$STRIPPED" | grep -iqE '\bDROP\s+(TABLE|VIEW)\s+(IF\s+EXISTS\s+)?temp\.' \
         || echo "$COMMAND"  | grep -iqE '\bDROP\s+(TEMP|TEMPORARY)\s+(TABLE|VIEW)\b' \
         || echo "$COMMAND"  | grep -iqE '\bDROP\s+(TABLE|VIEW)\s+(IF\s+EXISTS\s+)?temp\.'; then
        : # temporary object teardown: allowed
      else
        echo "BLOCKED [effort=$EFFORT]: DROP TABLE/VIEW detected. Use a migration instead." >&2
        exit 2
      fi
    fi

    # DELETE without WHERE. The WHERE is searched in the SAME form where the DELETE was
    # found: mixing forms gives a false positive on the single-quoted form that HAS a WHERE.
    if echo "$STRIPPED" | grep -iqE '\bDELETE\b' && ! echo "$STRIPPED" | grep -iqE '\bWHERE\b'; then
      echo "BLOCKED [effort=$EFFORT]: DELETE without WHERE clause detected." >&2
      exit 2
    fi
    if echo "$COMMAND" | grep -iqE '\bDELETE\b' && ! echo "$COMMAND" | grep -iqE '\bWHERE\b'; then
      echo "BLOCKED [effort=$EFFORT]: DELETE without WHERE clause detected (single-quoted form). If this is prose and not SQL, rephrase it without the verb next to the table name." >&2
      exit 2
    fi

    # TRUNCATE against a table, but not the WAL checkpoint mode of the same name.
    CKPT_SAFE=$(printf '%s' "$STRIPPED" \
      | sed -E 's/wal_checkpoint[[:space:]]*\([[:space:]]*(passive|full|restart|truncate)[[:space:]]*\)/wal_checkpoint()/Ig' \
      | sed -E 's/wal_checkpoint[[:space:]]*=[[:space:]]*(passive|full|restart|truncate)/wal_checkpoint=/Ig')
    TRUNCATE_RE="(^|[;\"'\`])[[:space:]]*TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[A-Za-z_\"\`[]"
    if echo "$CKPT_SAFE" | grep -iqE "$TRUNCATE_RE"; then
      echo "BLOCKED [effort=$EFFORT]: TRUNCATE against a table detected. Use DELETE ... WHERE, or a migration. (PRAGMA wal_checkpoint(TRUNCATE) is allowed.)" >&2
      exit 2
    fi

    # Writes and DDL on spec_criteria outside scripts/spec_criteria.py. The criteria state
    # changes only through the script, which also writes the activity_history row; the
    # triggers of migration 027 are not dropped by hand. No \b before spec_criteria in the
    # DDL pattern: trigger names start with trg_spec_criteria_, and `_` is a word character.
    SPEC_WRITE_RE='\b(INSERT|UPDATE|REPLACE)\b[^;]*\bspec_criteria\b'
    SPEC_DDL_RE='\b(DROP[[:space:]]+TRIGGER|ALTER[[:space:]]+TABLE)\b[^;]*spec_criteria'
    if echo "$COMMAND"  | grep -iqE "$SPEC_WRITE_RE|$SPEC_DDL_RE" \
       || echo "$STRIPPED" | grep -iqE "$SPEC_WRITE_RE|$SPEC_DDL_RE"; then
      if ! echo "$COMMAND" | grep -q 'spec_criteria\.py'; then
        echo "BLOCKED [effort=$EFFORT]: direct write or DDL on spec_criteria. Criteria state changes only through 'python3 scripts/spec_criteria.py <claim|verify|fail|waive|close>', which also logs to activity_history; the triggers of migration 027 are not dropped by hand. If this is prose and not SQL, rephrase it without the table name next to the verb." >&2
        exit 2
      fi
    fi
    ;;
esac
exit 0
