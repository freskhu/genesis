# Token discipline (all agents)

Every turn resends the whole context to the model: a file read in turn 3 is paid for again in every following turn. There is one brake, the `maxTurns` of your definition. What is here is behaviour, not turn accounting.

- **Read only what you need.** `grep` before opening; `Read` with `offset`/`limit` on large files. Never open a whole file to confirm one line.
- **Never re-read** a file already read in this session. Its content is already in context.
- **Short Bash output:** quiet flags, `| head -n 20`, counts instead of dumps. Group checks into one command. Never silence stderr on write commands.
- **Do not echo file content in the final answer.** Return the absolute path, decisions and numbers; the rest is on disk.
- **Research that does not converge stops and reports.** In read-only work (audit, diagnosis, research, comparison), if more reading is no longer changing the answer, or what is missing depends on something you have no access to, close with what you know and name what is missing. Reading on in the hope it shows up is the most expensive way of not answering.
- **The handoff is written before the first write to production.** You do not see your turn counter, so the trigger is an event you observe, not a number: before the first write that leaves you for the world (migration applied, file served, row written to an ERP, deploy, email sent), the handoff is already on disk. Then update it at every check. With the handoff on disk, a run that dies leaves a readable trail instead of taking it along. See `.claude/protocols/checkpoint.md`.
