# Resuming long tasks (handoff on disk)

**Trigger:** long tasks (more than ~15 turns), processing many documents, complex builds, or an agent failure mid-task.

**Why this changed.** An earlier version of this protocol asked agents to write a JSON checkpoint into `tasks.description` after every step. Measured over months in the reference instance: almost no task ever carried a checkpoint, while hundreds of handoff files were written to disk and used to resume. Resuming never went through the database. It goes through the handoff, so the protocol points at the mechanism that is actually used.

## The resume artefact is the handoff on disk

Whoever does the work writes a handoff file in the right subfolder of `outbox/`, named `<date>-<slug>-handoff.md`, and updates it at every check. The trigger is not a number of turns, it is an observable event: **before the first write that leaves the agent for the world** (migration applied, file served, row written to an ERP, deploy, email sent), the handoff is already on disk. Full rule in `.claude/rules/_agent-token-discipline.md`.

The handoff covers: where it stopped, what was decided and why, absolute paths touched, what is left, blockers, and what was tried and did not work.

Besides the file, the agent returns the handoff block in its answer (`.claude/protocols/agent-outputs.md`): *What was done / What was decided / What's left / Blockers*. One is for resuming, the other is for the orchestrator to verify without opening the file.

## Recovering from a failure mid-task

When an agent dies (error, context overflow, `maxTurns`):

1. Look for the handoff: `ls -t "outbox/<project>/"*handoff*` and, if the agent did not name it, `find "outbox" -iname "*<slug>*" -mtime -1`.
2. If it exists, relaunch with the handoff path in the dispatch: *"resume from this handoff: `<path>`. Do not redo what it lists as done."*
3. If it does not exist, there are two fallbacks, in order: the agent's diary (`palace.py search "<slug>"`, which covers `diary_entries`) and the run transcript. Only after both fail, tell the owner the progress was lost and ask whether to restart or abandon.

An agent that dies **without** a handoff on disk is a defect to report, not an accident: token discipline asks for it before the first write to production precisely for this case.

## What still holds

- Important intermediate results do not live only in the conversation.
- Documents: read, extract, save the extract, move on. Do not keep raw content in context.
- Learnings go to the palace (`palace.py add`) and observations to the diary (`palace.py diary-write`) as they happen, not at the end.
- `tasks` keeps recording operational state: `status`, `title`, owner. What was dropped is the **checkpoint JSON** in `tasks.description`, not the table.
- The palace auto-save (every 15 messages and before compaction) runs by hook and does not depend on anyone remembering.
