#!/usr/bin/env bash
# check_refs.sh -- every path the repo talks about must exist in the repo.
#
# Extracts references of the form .claude/..., scripts/..., docs/..., Team/..., Database/...
# and wrapper names ait-* from every tracked .md, .sh, .py and .json file, and checks that
# each one exists in the working tree (wrappers under scripts/bin/). A rule that names a
# script nobody shipped is a rule that cannot be followed.
#
# Skipped on purpose:
#   - references with placeholders: < > { } * YYYY ... (templates, not paths);
#   - files created at run time or by the user, listed in scripts/check_refs.allow
#     (one path per line, a reason after a tab);
#   - docs/sync-*-inventory.md, which names instance files that were NOT ported.
#   - test batteries (*.test.sh), whose paths are synthetic fixtures they create themselves.
#
# Usage:  bash scripts/check_refs.sh          (from anywhere inside the repo)
# Exit:   0 every reference resolves; 1 missing references (listed on stdout); 2 usage.
# Pure bash plus git, grep, sed and sort.
set -u
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || { echo "check_refs: not inside a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2
ALLOW_FILE="scripts/check_refs.allow"

allowed() {
  [ -f "$ALLOW_FILE" ] || return 1
  grep -v '^[[:space:]]*#' "$ALLOW_FILE" | cut -f1 | grep -qxF "$1"
}

missing=0
checked=0
while IFS= read -r file; do
  case "$file" in docs/sync-*-inventory.md|*.test.sh) continue ;; esac
  [ -f "$file" ] || continue
  # path references
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    ref="${ref%%[.,:;)\`\'\"]}"
    ref="${ref%%[.,:;)\`\'\"]}"
    case "$ref" in
      *'<'*|*'>'*|*'{'*|*'}'*|*'*'*|*YYYY*|*'...'*|*'$'*) continue ;;
    esac
    checked=$((checked+1))
    if [ -e "$ref" ] || allowed "$ref"; then continue; fi
    echo "MISSING  $ref   (in $file)"
    missing=$((missing+1))
  done < <(grep -oE '(^|[^A-Za-z0-9_./~-])(\.claude|scripts|docs|Team|Database)/[A-Za-z0-9_./<>{}*$-]+' "$file" \
             | sed -E 's#^[^.sdTD]*##' | sort -u)
  # wrapper names
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    checked=$((checked+1))
    if [ -e "scripts/bin/$w" ] || allowed "scripts/bin/$w"; then continue; fi
    echo "MISSING  scripts/bin/$w   (wrapper named in $file)"
    missing=$((missing+1))
  done < <(grep -oE '(^|[^A-Za-z0-9_/.-])ait-[a-z][a-z-]*[a-z]' "$file" | sed -E 's#^[^a]*##' \
             | grep -vxE 'ait-(config|runtime|data)' | sort -u)
done < <(git ls-files '*.md' '*.sh' '*.py' '*.json')

echo "check_refs: $checked references checked, $missing missing"
[ "$missing" -eq 0 ]
