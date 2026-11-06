#!/usr/bin/env bash
# spec-criteria-gate.sh -- PreToolUse (Agent|Task): ingests a spec's acceptance criteria at
# dispatch time.
#
# What it does: when a dispatch prompt cites a spec path `Team/_briefs/YYYY-MM-DD-*.md`,
# runs `scripts/spec_criteria.py ingest` on that file so each criterion is born as `fail`
# without anyone having to remember, and returns the count as additionalContext. A
# dispatch with no spec path is untouched (exit 0, no DB access): that is what exempts
# quick single-agent work.
#
# Script exit codes and what this hook does with them:
#   0 done                 -> exit 0 + additionalContext
#   6 spec has no criteria -> exit 2, BLOCKS (the only blocking policy: a spec without a
#                             contract is not dispatched; the way out is to add `- [ ]`
#                             boxes under "## Acceptance criteria")
#   4 infrastructure       -> exit 0, fail-open, loud warning + log line
#   2 invalid input        -> exit 0 + warning (a mistyped path in prose is not a reason
#   3 spec not found       -> exit 0 + warning  to stop a dispatch; nor is a spec the
#                                                agent is about to create)
#
# Fail-open: no jq, no python3, no DB, no script -> exit 0 silently with a log line.
# Blocking only by policy, never because a tool is missing.
#
# Specs dated before SPEC_CRITERIA_GATE_SINCE (YYYY-MM-DD, optional) are neither ingested
# nor blocked: set it to the day you install the mechanism, so older specs written without
# boxes do not block re-dispatches.
#
# Note: --db and --workspace are GLOBAL options of the script and go BEFORE the subcommand.
# Log: $GENESIS_LOG_DIR/spec-criteria-gate.log (one line per decision)
# Test: .claude/hooks/spec-criteria-gate.test.sh
set -u

WS="${SPEC_CRITERIA_WORKSPACE:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" || exit 0
DB="${SPEC_CRITERIA_DB:-$WS/Database/team.db}"
SCRIPT="${SPEC_CRITERIA_SCRIPT:-$WS/scripts/spec_criteria.py}"
LOG="${SPEC_CRITERIA_GATE_LOG:-${GENESIS_LOG_DIR:-$HOME/.mempalace/logs}/spec-criteria-gate.log}"
SINCE="${SPEC_CRITERIA_GATE_SINCE:-}"

log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >>"$LOG" 2>/dev/null || true
}
context() {
  [ -n "$1" ] || exit 0
  jq -n --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
  exit 0
}

command -v jq >/dev/null 2>&1 || { log "fail-open: no jq"; exit 0; }
INPUT=$(cat 2>/dev/null || true)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in Agent|Task|"") ;; *) exit 0 ;; esac
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
AUTHOR=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
[ -n "$PROMPT" ] || exit 0

SPECS=$(printf '%s' "$PROMPT" | grep -oE 'Team/_briefs/[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9._-]+\.md' | sort -u)
[ -n "$SPECS" ] || exit 0

command -v python3 >/dev/null 2>&1 || { log "fail-open: no python3"; exit 0; }
[ -f "$SCRIPT" ] || { log "fail-open: no script $SCRIPT"; exit 0; }
[ -f "$DB" ] || { log "fail-open: no DB $DB"; exit 0; }

MSG=""
while IFS= read -r SPEC; do
  [ -n "$SPEC" ] || continue
  SPEC_DATE=$(printf '%s' "$SPEC" | sed -E 's#^Team/_briefs/([0-9]{4}-[0-9]{2}-[0-9]{2}).*#\1#')
  if [ -n "$SINCE" ] && [[ "$SPEC_DATE" < "$SINCE" ]]; then
    log "skip (before $SINCE): $SPEC"; continue
  fi
  OUT=$(python3 "$SCRIPT" --db "$DB" --workspace "$WS" ingest --spec "$SPEC" ${AUTHOR:+--author "$AUTHOR"} 2>&1)
  RC=$?
  log "rc=$RC spec=$SPEC author=${AUTHOR:-?}"
  case "$RC" in
    0) MSG="${MSG}SPEC CRITERIA: $OUT. The author claims each criterion with evidence (scripts/spec_criteria.py claim); someone else verifies. "
       ;;
    6) echo "BLOCKED (spec-criteria-gate): $SPEC has no acceptance criteria. Add one \`- [ ]\` box per criterion under '## Acceptance criteria', each checkable by a file, a command or a row, then dispatch again." >&2
       exit 2 ;;
    4) MSG="${MSG}SPEC CRITERIA (warning): could not ingest $SPEC, infrastructure error: $(printf '%s' "$OUT" | tail -n 1 | cut -c1-160). Criteria are NOT being tracked for this dispatch. "
       ;;
    *) MSG="${MSG}SPEC CRITERIA (warning): $SPEC not ingested (rc=$RC: $(printf '%s' "$OUT" | tail -n 1 | cut -c1-160)). "
       ;;
  esac
done <<EOF
$SPECS
EOF

context "$MSG"
