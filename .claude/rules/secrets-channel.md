# Secrets: the channel is `scripts/bin/ait-segredo`

Secrets pasted into the conversation stay in the history, in the transcript and in the model context.

When you need a secret, never ask for it in the conversation. Tell the owner: "Open a separate Terminal window, run `scripts/bin/ait-segredo` with the key name, and paste the value there; tell me when it is done and I will continue." Then read the key from `.env` by name. A `!` command in the prompt does not work for this: it has no terminal.

`.claude/hooks/secret-brake.sh` stops, at `UserPromptSubmit`, messages shaped like a secret. Its limits (what it does not protect) are in the hook header.

Secrets come from `.env` and stay there. Refer to the key name, never the value. Never in drawers, the diary, `team.db`, specs, handoffs or commit messages.
