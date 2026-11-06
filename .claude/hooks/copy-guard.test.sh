#!/usr/bin/env bash
# copy-guard.test.sh -- test battery for copy-guard.sh with a temporary config.
# Run: bash .claude/hooks/copy-guard.test.sh   Exit 0 = all pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/copy-guard.sh}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/copyguard-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/conf" <<'CONF'
# test config
protect (^|[^A-Za-z0-9_.-])people\.db([^A-Za-z0-9_-]|$)
protect prod-db-host
allow   data/backups/people-[0-9]{8}-[0-9]{4,6}(-[A-Za-z0-9._-]+)?\.db
CONF
export COPY_GUARD_CONF="$TMP/conf"
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
run() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$HOOK" >/dev/null 2>"$TMP/err"; echo $?; }
blocks() { [ "$(run "$2")" = 2 ] && ok "blocks: $1" || ko "blocks: $1"; }
passes() { [ "$(run "$2")" = 0 ] && ok "passes: $1" || ko "passes: $1"; }

[ -x "$HOOK" ] && ok "hook is executable" || ko "hook is not executable"

blocks "cp to the scratchpad" 'cp data/people.db /tmp/x.db'
blocks "cp with absolute path" 'cp "/srv/app/data/people.db" ~/Desktop/'
blocks "rsync" 'rsync -a data/people.db backup-host:/x/'
blocks "sqlite3 .backup" 'sqlite3 data/people.db ".backup /tmp/p.db"'
blocks "VACUUM INTO" "sqlite3 data/people.db \"VACUUM INTO '/tmp/p.db'\""
blocks "pg_dump of the protected host" 'pg_dump -h prod-db-host app > dump.sql'
blocks "second segment after &&" 'ls && cp data/people.db /tmp/'
blocks "through xargs" 'echo data/people.db | xargs cp -t /tmp'
blocks "sudo prefix" 'sudo cp data/people.db /tmp/'
grep -q 'mode=ro' "$TMP/err" && ok "message shows how to read in place" || ko "no read-in-place hint"

passes "copy to the allowed destination" 'cp data/people.db data/backups/people-20260101-1200-migration.db'
passes "read in place" 'sqlite3 "file:data/people.db?mode=ro" "SELECT COUNT(*) FROM t"'
passes "copy of another file" 'cp notes.md /tmp/'
passes "people.db mentioned in echo prose" 'echo "never cp people.db anywhere" >> notes.md'
passes "people.db in a heredoc body" "$(printf 'cat > n.md <<EOF\ncp data/people.db /tmp/\nEOF')"
passes "similar name is not the protected one" 'cp data/peoplex.db /tmp/'
passes "ls of the protected file" 'ls -l data/people.db'

printf '# nothing protected\n' > "$TMP/empty"
R=$(jq -n --arg c 'cp data/people.db /tmp/' '{tool_input:{command:$c}}' | COPY_GUARD_CONF="$TMP/empty" bash "$HOOK" 2>/dev/null; echo $?)
[ "$R" = 0 ] && ok "no protect line: guard off" || ko "empty config"
R=$(jq -n --arg c 'cp data/people.db /tmp/' '{tool_input:{command:$c}}' | COPY_GUARD_CONF=/does/not/exist bash "$HOOK" 2>/dev/null; echo $?)
[ "$R" = 0 ] && ok "missing config: fail-open" || ko "missing config"
printf 'not json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "fail-open on invalid JSON" || ko "invalid JSON"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
