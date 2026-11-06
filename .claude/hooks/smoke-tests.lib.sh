#!/usr/bin/env bash
# smoke-tests.lib.sh -- shared helpers for the minimal smoke tests of hooks that have no
# full battery yet. Sourced by <hook>.test.sh; not a test itself (no .test.sh suffix).
#
# A smoke test proves three things: the hook is executable, it runs on realistic input
# without crashing, and it returns the documented exit code. It does not prove the hook's
# logic; a full battery does.
set -u
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/hook-smoke.XXXXXX")
trap 'rm -rf "$SMOKE_TMP"' EXIT
export HOME="$SMOKE_TMP/home"; mkdir -p "$HOME"
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

# copy_tree <hook>: copies the hook into a throwaway project tree with an empty database
# built from Database/schema.sql, and prints the path of the copied hook.
copy_tree() {
  local repo t
  repo="$(cd "$HOOKS_DIR/../.." && pwd)"
  t="$SMOKE_TMP/proj"
  mkdir -p "$t/.claude/hooks" "$t/Database" "$t/scripts" "$t/outbox"
  cp "$HOOKS_DIR/$1" "$t/.claude/hooks/"
  sqlite3 "$t/Database/team.db" < "$repo/Database/schema.sql" >/dev/null 2>&1
  printf 'import sys\nsys.exit(0)\n' > "$t/scripts/generate_memory_hot.py"
  printf '%s' "$t/.claude/hooks/$1"
}

# expect_rc <name> <expected rc> <hook path> <stdin json>
expect_rc() {
  local rc
  printf '%s' "$4" | bash "$3" >"$SMOKE_TMP/out" 2>"$SMOKE_TMP/err"; rc=$?
  [ "$rc" = "$2" ] && ok "$1 (rc=$rc)" || ko "$1 (want rc=$2, got rc=$rc: $(head -c 200 "$SMOKE_TMP/err"))"
}

smoke_done() { echo; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ] || exit 1; }
