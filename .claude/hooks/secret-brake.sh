#!/usr/bin/env bash
# secret-brake.sh -- UserPromptSubmit: stops messages that look like they carry a secret.
#
# Why it exists: secrets pasted into the prompt end up in the conversation history, in the
# session transcript and in the model context. A written rule ("never paste keys") does not
# stop it; a hook that refuses the message does. Detection is by format only: known token
# prefixes, JWTs, and labelled values ("password: ...", "private key ... <64 hex>").
# Deliberately narrow: bare hex, UUIDs and unprefixed base64 pass, because widening the net
# would stop commit hashes and session ids.
#
# Contract: exit 2 when it catches something, exit 0 otherwise, fail-open on any error.
# The output never echoes what was caught, nor which format matched. Nothing is written.
# No model call. Silent in headless runs (CLAUDE_CODE_ENTRYPOINT=sdk-cli): nobody pastes
# into a scheduled routine.
#
# What it does NOT protect (measured on a test token):
#   - It stops the write to the prompt history and the send to the model.
#   - Claude Code itself may still print the original prompt in the terminal and keep it in
#     a `system` line of the session transcript.
#   - Hooks run in parallel: any other hook on this event still receives the prompt.
#
# The safe channel: .claude/rules/secrets-channel.md (scripts/bin/ait-segredo).
# Let a false positive through: start the message with `pass:`.
#
# Test: .claude/hooks/secret-brake.test.sh
# Rollback: remove the UserPromptSubmit block for this hook from .claude/settings.json.

[ "${CLAUDE_CODE_ENTRYPOINT:-cli}" = "sdk-cli" ] && { cat >/dev/null; exit 0; }

MESSAGE='This message looks like it carries a secret, so it was not sent. Open a separate terminal window, run `scripts/bin/ait-segredo` with the key name, and paste the value there; then tell me the key name. Do not use `!` in the conversation. If this was a false positive, resend the message starting with `pass:`.'

python3 -I -c '
import json, re, sys

FORMATS = re.compile(
    r"sk-ant-[A-Za-z0-9_-]{20,}"
    r"|\bsk-(?:proj-|or-)?[A-Za-z0-9_-]{32,}"
    r"|\bgh[pousr]_[A-Za-z0-9]{30,}"
    r"|\bgithub_p[a]t_[A-Za-z0-9_]{30,}"
    r"|\bxox[bpars]-[0-9]{6,}-[0-9A-Za-z-]{10,}"
    r"|\bxapp-[0-9]-[A-Za-z0-9-]{20,}"
    r"|\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}"
    r"|\bsbp_[0-9a-f]{30,}"
    r"|\bsb_secret_[0-9A-Za-z_-]{16,}"
    r"|\bvc[pkia]_[0-9A-Za-z]{20,}"
    r"|\bEAA[A-Za-z0-9]{60,}"
    r"|\bATTA[0-9A-Fa-f]{40,}"
    r"|\bre_[A-Za-z0-9]{8,}_[A-Za-z0-9]{16,}"
    r"|\bGOCSPX-[0-9A-Za-z_-]{16,}"
    r"|[A-Za-z0-9_.~-]{3}[0-9]Q~[A-Za-z0-9_.~-]{20,}"
    r"|\bsk_[0-9a-f]{40,}"
    r"|(?i:private[ _-]?key|private)\W{0,12}(?:\w+\W{0,3}){0,4}(?:0x)?[a-fA-F0-9]{64}\b"
    r"|(?i:\b(?:password|passwd|pwd|pass|passphrase)\s*[:=]\s*)\S{6,}"
)

try:
    prompt = str(json.load(sys.stdin).get("prompt") or "")
except Exception:
    sys.exit(0)

if prompt.lstrip().lower().startswith("pass:"):
    sys.exit(0)
if FORMATS.search(prompt):
    sys.exit(2)
'
[ $? -eq 2 ] && { printf '%s\n' "$MESSAGE" >&2; exit 2; }
exit 0
