#!/usr/bin/env bash
# correction-nudge.sh -- UserPromptSubmit: nudge from the second correction in a session on.
#
# Why it exists: repeated corrections in the same session are the expensive ones. The first
# never nudges; the second and later inject a short reminder (re-read the last claim, cite
# a source, pass the correction to any running agent in the owner's words).
#
# Contract: always a nudge, never a block; exit 0 always; fail-open. No model call. Stores
# only date, session id and family (see scripts/corrections.py); never the message text.
# Counter per exact session_id. Silent in headless runs.
#
# Measure whether it helps: python3 scripts/corrections.py measure
# Decide up front what result keeps it, and remove it if the share of repeat corrections
# does not drop.
# Test: .claude/hooks/correction-nudge.test.sh
# Rollback: remove the UserPromptSubmit block for this hook from .claude/settings.json.

[ "${CLAUDE_CODE_ENTRYPOINT:-cli}" = "sdk-cli" ] && { cat >/dev/null; exit 0; }

PROJECT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SCRIPT="${CORRECTIONS_SCRIPT:-$PROJECT/scripts/corrections.py}"
python3 "$SCRIPT" hook 2>/dev/null
exit 0
