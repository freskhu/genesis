#!/usr/bin/env bash
# copy-guard.sh -- PreToolUse (Bash): blocks copies of databases that hold personal data.
#
# Why it exists: if an agent copies a database with people's personal data into a session
# scratchpad "just to read it", nobody can say afterwards where the copy is. There is no
# code to fix: it is behaviour. This hook is the deterministic
# edge of .claude/rules/personal-data-db-access.md: read in place, never copy; and when a
# copy is truly needed (to rehearse a write), it is born where the retention routine of
# that system sweeps it.
#
# BLOCKS (exit 2) a command segment that:
#   - runs cp, rsync or scp, and names a protected database (file or data directory);
#   - runs sqlite3 with .backup, .dump or VACUUM INTO on a protected database;
#   - runs pg_dump (or `supabase db dump`) naming a protected target;
# unless the same segment names an allowed destination.
#
# Configuration: .claude/hooks/copy-guard.conf (override with COPY_GUARD_CONF).
#   protect <ERE>   a protected database file or directory
#   allow   <ERE>   an allowed copy destination (where the retention routine sweeps)
# With no `protect` line the hook does nothing.
#
# Limits: text-based. Prose inside echo/printf and heredoc bodies is ignored, and the
# command is split on && || ; and |. A script that builds the path at run time goes around
# it: this guards against mistakes, not against an adversary.
# Test: .claude/hooks/copy-guard.test.sh
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0
case "$COMMAND" in
  *cp*|*rsync*|*scp*|*sqlite3*|*pg_dump*|*supabase*) ;;
  *) exit 0 ;;
esac

CONF="${COPY_GUARD_CONF:-$(cd "$(dirname "$0")" && pwd)/copy-guard.conf}"
[ -r "$CONF" ] || exit 0
PROTECT_RE=$(awk '$1=="protect"{ $1=""; sub(/^ +/,""); print }' "$CONF" | paste -sd'|' -)
ALLOW_RE=$(awk '$1=="allow"{ $1=""; sub(/^ +/,""); print }' "$CONF" | paste -sd'|' -)
[ -z "$PROTECT_RE" ] && exit 0

EFFORT="${CLAUDE_EFFORT:-$(echo "$INPUT" | jq -r '.effort.level // empty' 2>/dev/null || true)}"
EFFORT="${EFFORT:-n/a}"

# Drop heredoc bodies, then quoted prose after echo/printf and commit messages.
NOHEREDOC=$(printf '%s\n' "$COMMAND" | awk '
  { if (skip) { if ($0 == delim) skip=0; next }
    line=$0
    if (match(line, /<<-?[ ]*[\x27"]?[A-Za-z_][A-Za-z0-9_]*[\x27"]?/)) {
      d=substr(line, RSTART, RLENGTH); gsub(/^<<-?[ ]*|[\x27"]/, "", d)
      delim=d; skip=1
    }
    print line }')
CLEAN=$(printf '%s' "$NOHEREDOC" | perl -0pe '
  s/\b(echo|printf)\b((\s+-[A-Za-z]+)*)\s*("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/$1/g;
  s/(-m|--message)\s*("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/$1/g;
' 2>/dev/null || printf '%s' "$NOHEREDOC")

# verb_of <segment>: the command word, after env assignments, sudo/nohup/env/time/xargs.
verb_of() {
  perl -e '
    my $s = <STDIN>; $s = "" unless defined $s; chomp $s; $s =~ s/^\s+//;
    while ($s =~ s{^(?:[A-Za-z_][A-Za-z0-9_]*=\S*|sudo|nohup|command|env|time)\s+}{}) {}
    if ($s =~ s{^xargs\s+}{}) { $s =~ s{^(?:-{1,2}[A-Za-z0-9]\S*\s+|\{\}\s+|[0-9]+\s+)*}{}; }
    $s =~ s{^(?:ba|z)?sh\s+-c\s+["\x27]?}{};
    my ($w) = $s =~ /^(\S+)/; $w = "" unless defined $w; $w =~ s{^.*/}{};
    print $w;
  ' <<< "$1"
}

BLOCK_MSG=""
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  SEG_DQ=$(printf '%s' "$SEG" | tr -d "\"'")
  printf '%s' "$SEG_DQ" | grep -qE "$PROTECT_RE" || continue
  if [ -n "$ALLOW_RE" ] && printf '%s' "$SEG_DQ" | grep -qE "$ALLOW_RE"; then
    continue
  fi
  # The protected/allowed test above applies to the whole segment (split on && || ;), so
  # `echo people.db | xargs cp -t /tmp` stays one segment. The verb is looked up per
  # pipeline stage.
  while IFS= read -r STAGE || [ -n "$STAGE" ]; do
    [ -z "$STAGE" ] && continue
    VERB=$(verb_of "$STAGE")
    case "$VERB" in
      cp|rsync|scp) BLOCK_MSG="$VERB of a protected database" ;;
      sqlite3)
        printf '%s' "$STAGE" | grep -qiE '(\.backup|\.dump|VACUUM[[:space:]]+INTO)' \
          && BLOCK_MSG="sqlite3 copying a protected database" ;;
      pg_dump) BLOCK_MSG="pg_dump of a protected database" ;;
      supabase)
        printf '%s' "$STAGE" | tr -d "\"'" | grep -qE '(^|[[:space:]])db[[:space:]]+dump' \
          && BLOCK_MSG="database dump of a protected target" ;;
    esac
    [ -n "$BLOCK_MSG" ] && break
  done < <(printf '%s\n' "$SEG" | tr '|' '\n')
  [ -n "$BLOCK_MSG" ] && break
done <<EOF
$(printf '%s' "$CLEAN" | sed -E 's/(&&|\|\||;)/\n/g')
EOF

if [ -n "$BLOCK_MSG" ]; then
  cat >&2 <<MSG
BLOCKED [effort=$EFFORT]: $BLOCK_MSG.
To READ, read in place, without creating any copy:
  sqlite3 "file:<db>?mode=ro" "<query>"     # closed DB with no -wal file: ?immutable=1
To REHEARSE A WRITE, the copy is born WHERE THE SYSTEM'S RETENTION ROUTINE SWEEPS IT
(the 'allow' lines of .claude/hooks/copy-guard.conf), with chmod 600, and a trap deletes
it at the end of the rehearsal.
Never: /tmp, the session scratchpad, Downloads, Desktop, outbox, a dev worktree.
Rule: .claude/rules/personal-data-db-access.md
MSG
  exit 2
fi
exit 0
