#!/usr/bin/env bash
# sql-guardrails.test.sh -- test battery for sql-guardrails.sh: the spec_criteria guard plus
# regression of the older guards.
#
# The test commands live INSIDE this file on purpose: the hook reads the command line, so a
# case with a destructive verb typed into an interactive Bash command is stopped by the live
# hook before it reaches the test. File content always passes.
#
# Run: bash .claude/hooks/sql-guardrails.test.sh   Exit 0 = all pass.
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/sql-guardrails.sh"
PASS=0; FAIL=0

run() {  # $1 = command to simulate -> RC
    RC=$(python3 -c "
import json,subprocess,sys
cmd=sys.argv[1]
p=subprocess.run(['bash',sys.argv[2]],input=json.dumps({'tool_input':{'command':cmd}}),
                 capture_output=True,text=True)
print(p.returncode)
" "$1" "$HOOK")
}
expect() {  # $1 name  $2 expected (0|2)  $3 command
    run "$3"
    if [ "$RC" = "$2" ]; then PASS=$((PASS+1)); printf '  OK   %s\n' "$1"
    else FAIL=$((FAIL+1)); printf '  FAIL %s (expected rc=%s, got rc=%s)\n' "$1" "$2" "$RC"; fi
}

echo "== sql-guardrails: spec_criteria =="
expect "S01 direct UPDATE on spec_criteria blocks" 2 \
  "sqlite3 Database/team.db \"UPDATE spec_criteria SET status='verified' WHERE id=1;\""
expect "S02 direct INSERT on spec_criteria blocks" 2 \
  "sqlite3 Database/team.db \"INSERT INTO spec_criteria (spec_path,text) VALUES ('a','b');\""
expect "S03 direct REPLACE on spec_criteria blocks" 2 \
  "sqlite3 Database/team.db \"REPLACE INTO spec_criteria (id,text) VALUES (1,'x');\""
expect "S04 through the script passes" 0 \
  "python3 scripts/spec_criteria.py verify --spec Team/_briefs/x.md --criterion 1 --by reviewer"
expect "S05 script with UPDATE inside --note passes" 0 \
  "python3 scripts/spec_criteria.py fail --spec Team/_briefs/x.md --criterion 1 --by reviewer --note 'the UPDATE spec_criteria step failed'"
expect "S06 SELECT on spec_criteria passes" 0 \
  "sqlite3 Database/team.db \"SELECT status FROM spec_criteria;\""
expect "S07 INSERT into another table passes" 0 \
  "sqlite3 Database/team.db \"INSERT INTO activity_history (actor_id,action) VALUES (1,'spec_review');\""
expect "S08 prose in echo passes (no sqlite3 in the command)" 0 \
  "echo 'never UPDATE spec_criteria by hand' >> notes.md"

echo "== single-quoted (idiomatic) form =="
expect "S14 UPDATE with single quotes blocks" 2 \
  "sqlite3 Database/team.db 'UPDATE spec_criteria SET status=1'"
expect "S15 INSERT with single quotes blocks" 2 \
  "sqlite3 Database/team.db 'INSERT INTO spec_criteria (spec_path) VALUES (1)'"
expect "S16 DROP TRIGGER of a spec_criteria guard blocks" 2 \
  "sqlite3 Database/team.db 'DROP TRIGGER trg_spec_criteria_no_delete'"
expect "S17 ALTER TABLE spec_criteria blocks" 2 \
  "sqlite3 Database/team.db 'ALTER TABLE spec_criteria RENAME TO x'"
expect "S18 DROP TRIGGER unrelated to spec_criteria passes" 0 \
  "sqlite3 Database/team.db 'DROP TRIGGER trg_something_else'"
expect "S19 ALTER TABLE on another table passes" 0 \
  "sqlite3 Database/team.db 'ALTER TABLE tasks ADD COLUMN x TEXT'"

echo "== older guards not degraded =="
expect "S20 grep of prose with DELETE FROM tasks passes" 0 \
  "grep 'DELETE FROM tasks' notes.md"
expect "S21 DELETE FROM tasks with WHERE passes" 0 \
  "sqlite3 Database/team.db 'DELETE FROM tasks WHERE id=1'"
expect "S23 known narrow false positive: prose inside a command that runs sqlite3" 2 \
  "echo 'careful with UPDATE spec_criteria' && sqlite3 Database/team.db 'SELECT 1'"
expect "S09 DROP TABLE blocks" 2 \
  "sqlite3 Database/team.db \"DROP TABLE spec_criteria;\""
expect "S10 DROP TEMP TABLE passes" 0 \
  "sqlite3 Database/team.db \"DROP TEMP TABLE t;\""
expect "S11 DELETE without WHERE blocks" 2 \
  "sqlite3 Database/team.db \"DELETE FROM spec_criteria;\""
expect "S12 PRAGMA wal_checkpoint(TRUNCATE) passes" 0 \
  "sqlite3 Database/team.db \"PRAGMA wal_checkpoint(TRUNCATE);\""
expect "S12b TRUNCATE TABLE blocks" 2 \
  "sqlite3 Database/team.db \"TRUNCATE TABLE tasks;\""
expect "S13 command without SQL passes" 0 "ls -l Database/"
expect "S24 DELETE without WHERE in single quotes blocks" 2 \
  "sqlite3 Database/team.db 'DELETE FROM tasks'"
expect "S25 DROP TABLE in single quotes blocks" 2 \
  "sqlite3 Database/team.db 'DROP TABLE tasks'"
expect "S26 DELETE with WHERE in single quotes passes" 0 \
  "sqlite3 Database/team.db 'DELETE FROM tasks WHERE id=1'"
expect "S27 temporary object in single quotes passes" 0 \
  "sqlite3 Database/team.db 'DROP TEMP TABLE t'"
expect "S29 the same prose without sqlite3 in the command passes" 0 \
  "echo 'careful with DELETE FROM tasks' >> notes.md"

printf '\n== %d OK, %d FAIL ==\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
