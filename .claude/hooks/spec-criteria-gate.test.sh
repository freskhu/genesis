#!/usr/bin/env bash
# spec-criteria-gate.test.sh -- test battery for spec-criteria-gate.sh AND for
# scripts/spec_criteria.py with migration 027, on a temporary workspace and database.
# Run: bash .claude/hooks/spec-criteria-gate.test.sh   Exit 0 = all pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
HOOK="${HOOK:-$HERE/spec-criteria-gate.sh}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/specgate-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
WS="$TMP/ws"; mkdir -p "$WS/Team/_briefs" "$WS/Database"
DB="$WS/Database/team.db"
sqlite3 "$DB" < "$REPO/Database/schema.sql" >/dev/null
sqlite3 "$DB" < "$REPO/Database/migrations/027_spec_criteria.sql" >/dev/null
sqlite3 "$DB" "INSERT INTO team_members (name, role) VALUES ('author-agent','test'),('reviewer','test'),('orchestrator','test');" >/dev/null
export SPEC_CRITERIA_WORKSPACE="$WS" SPEC_CRITERIA_DB="$DB" SPEC_CRITERIA_SCRIPT="$REPO/scripts/spec_criteria.py"
export GENESIS_LOG_DIR="$TMP/logs"
SC() { python3 "$REPO/scripts/spec_criteria.py" --db "$DB" --workspace "$WS" "$@" >"$TMP/sc.out" 2>&1; echo $?; }
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
is() { [ "$2" = "$3" ] && ok "$1" || ko "$1 (want $3, got $2)"; }
dispatch() { jq -n --arg p "$1" '{tool_name:"Agent",tool_input:{subagent_type:"author-agent",prompt:$p}}' | bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; echo $?; }

S=Team/_briefs/2030-01-01-sample.md
cat > "$WS/$S" <<'SPEC'
# SPEC: sample

## Objective
Something.

## Acceptance criteria
<!-- comment -->
- [ ] C1. The file exists.
- [ ] C2. The command exits 0
  when run twice.
- [ ] C3. The report is saved.

1. A numbered list item is not a criterion.

## Scope
- [ ] Not a criterion either.
SPEC
cat > "$WS/Team/_briefs/2030-01-02-empty.md" <<'SPEC'
# SPEC: empty
## Acceptance criteria
1. numbered only
SPEC

[ -x "$HOOK" ] && ok "hook is executable" || ko "hook is not executable"

# --- hook
is "dispatch without spec path: exit 0" "$(dispatch 'just do it')" 0
[ ! -s "$TMP/out" ] && ok "dispatch without spec path: no output" || ko "no output expected"
is "dispatch with spec: exit 0" "$(dispatch "read $S and work")" 0
grep -q '3 criteria' "$TMP/out" && ok "context reports 3 criteria" || ko "count in context"
is "spec without boxes blocks" "$(dispatch 'see Team/_briefs/2030-01-02-empty.md')" 2
grep -q 'Acceptance criteria' "$TMP/err" && ok "block message says how to fix" || ko "block message"
is "missing spec: warning, not a block" "$(dispatch 'see Team/_briefs/2030-01-03-missing.md')" 0
grep -q 'warning' "$TMP/out" && ok "missing spec warns" || ko "missing spec warns"
is "another tool: out of scope" "$(jq -n '{tool_name:"Bash",tool_input:{command:"x"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)" 0
is "older spec than SINCE: skipped" "$(SPEC_CRITERIA_GATE_SINCE=2031-01-01 dispatch 'see Team/_briefs/2030-01-02-empty.md')" 0
is "no DB: fail-open" "$(SPEC_CRITERIA_DB=/does/not/exist dispatch 'see Team/_briefs/2030-01-02-empty.md')" 0

# --- script: life cycle
is "ingest is idempotent" "$(SC ingest --spec $S)" 0
grep -q '0 new' "$TMP/sc.out" && ok "second ingest adds nothing" || ko "second ingest"
is "continuation line joined" "$(sqlite3 "$DB" "SELECT text FROM spec_criteria WHERE ordinal=2 AND status<>'superseded'")" "C2. The command exits 0 when run twice."
is "author recorded from the dispatch" "$(sqlite3 "$DB" "SELECT DISTINCT author FROM spec_criteria")" "author-agent"
is "claim without evidence refused" "$(SC claim --spec $S --criterion 1 --by author-agent --evidence ' ')" 2
is "claim with evidence" "$(SC claim --spec $S --criterion 1 --by author-agent --evidence 'out/file.md:1')" 0
is "author cannot verify" "$(SC verify --spec $S --criterion 1 --by author-agent)" 5
is "someone else verifies" "$(SC verify --spec $S --criterion 1 --by reviewer)" 0
is "fail criterion cannot be verified" "$(SC verify --spec $S --criterion 2 --by reviewer)" 5
is "waive needs a note" "$(SC waive --spec $S --criterion 3 --by orchestrator --note '')" 2
is "waive with the owner decision" "$(SC waive --spec $S --criterion 3 --by orchestrator --note 'owner: drop it')" 0
is "close refused while one is open" "$(SC close --spec $S)" 5
is "claim 2" "$(SC claim --spec $S --criterion 2 --by author-agent --evidence 'cmd rc=0')" 0
is "reviewer fails it" "$(SC fail --spec $S --criterion 2 --by reviewer --note 'did not open')" 0
is "status back to fail" "$(sqlite3 "$DB" "SELECT status FROM spec_criteria WHERE ordinal=2 AND status<>'superseded'")" fail
SC claim --spec $S --criterion 2 --by author-agent --evidence 'cmd rc=0 twice' >/dev/null
is "verify 2" "$(SC verify --spec $S --criterion 2 --by reviewer)" 0
is "close" "$(SC close --spec $S)" 0
is "close ticked the three boxes" "$(grep -c '^- \[x\] C' "$WS/$S")" 3
grep -q '^- \[ \] Not a criterion' "$WS/$S" && ok "boxes outside the section untouched" || ko "touched outside the section"
is "state changes logged" "$(sqlite3 "$DB" "SELECT COUNT(*)>=6 FROM activity_history WHERE action LIKE 'spec_criterion_%'")" 1

# --- text change supersedes
sed -i.bak 's/C3. The report is saved./C3. The report is saved and linked./' "$WS/$S" && rm -f "$WS/$S.bak"
is "ingest after a text change" "$(SC ingest --spec $S)" 0
is "old row superseded" "$(sqlite3 "$DB" "SELECT COUNT(*) FROM spec_criteria WHERE status='superseded'")" 1
is "new row born as fail" "$(sqlite3 "$DB" "SELECT status FROM spec_criteria WHERE text LIKE '%and linked.'")" fail

# --- triggers, in the data
is "trigger: no delete" "$(sqlite3 "$DB" "DELETE FROM spec_criteria WHERE id=1" 2>/dev/null; echo $?)" 1
is "trigger: text immutable" "$(sqlite3 "$DB" "UPDATE spec_criteria SET text='x' WHERE id=1" 2>/dev/null; echo $?)" 1
is "trigger: born as fail" "$(sqlite3 "$DB" "INSERT INTO spec_criteria (spec_path,ordinal,text,text_hash,status) VALUES ('$S',9,'t','$(printf 'a%.0s' $(seq 64))','verified')" 2>/dev/null; echo $?)" 1

# --- redacted mode
R=Team/_briefs/2030-01-04-health-plan.md
printf '# x\n## Acceptance criteria\n- [ ] A sensitive criterion text.\n' > "$WS/$R"
is "ingest of a redacted spec" "$(SC ingest --spec $R)" 0
is "stored text is a pointer" "$(sqlite3 "$DB" "SELECT text FROM spec_criteria WHERE spec_path='$R'")" "[criterion in file, line 3]"

# --- input
is "path outside Team/_briefs refused" "$(SC status --spec ../etc/passwd)" 2
is "missing DB is infrastructure" "$(python3 "$REPO/scripts/spec_criteria.py" --db /does/not/exist --workspace "$WS" status --spec $S >/dev/null 2>&1; echo $?)" 4

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
