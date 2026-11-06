#!/usr/bin/env bash
# voice-check.test.sh -- voice-check.sh is tested together with the /voice-gate checker,
# because both must agree on what counts as prose. This runs that shared battery.
# Run: bash .claude/hooks/voice-check.test.sh   Exit 0 = all pass.
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -x "$HERE/voice-check.sh" ] || { echo "FAIL  hook is not executable"; exit 1; }
exec bash "$HERE/../skills/voice-gate/check.test.sh"
