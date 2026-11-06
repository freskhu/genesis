# Local permissions: behaviour

- **Matching is by literal prefix.** `ssh myhost "cmd"` passes; `ssh -o ConnectTimeout=5 myhost ...` does not, because the option comes before the host name and breaks the prefix.
- **Git in a repository outside the project folder: `git -C <path> <sub>`.** Never `cd <path>` chained with `git`: the chain breaks the match and falls back to the classifier.
- **A classifier refusal is reported, not worked around.** Do not rewrite the command to dodge the prefix, do not swap in an equivalent tool just to pass, do not run it through an intermediate script. The refusal is information: either an entry is missing, or the action should not happen.
- **An agent does not edit the file of its own permissions.** The classifier blocks it by design and it should stay that way. Ask the owner.
- **`push` stays out of new entries.** Prefix matching does not tell a normal push from a forced one, nor one branch from another.
- **Before a push, list `origin/<branch>..HEAD` by SHA and stop if there is a commit the agent did not make in this task.** The author name does not tell them apart when every commit carries the owner's name.
- **Test identity in a worktree: `GIT_AUTHOR_*` / `GIT_COMMITTER_*` or `git -c user.email=...`, never `git config`.** Without `--worktree`, `git config` writes to the configuration shared by the main repository and every worktree.
- **Granting new permissions needs the owner's written authorisation in the session, a backup of the settings file before editing, and an entry in the permissions registry** (scope, worst case, rollback). The knowledge architect keeps the registry; the owner decides.
- **Secrets:** they come from `.env` and stay there. Refer to the key name, never the value (`.claude/rules/secrets-channel.md`).
