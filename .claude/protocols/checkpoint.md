# Context Management Protocol (MANDATORY)

**Trigger:** Long tasks (>15 turns), multi-document processing, full reviews, complex builds, agent failure mid-task, or every 10-15 substantive interactions.

All state persistence goes to `Database/team.db`. NEVER use temporary files, markdown checkpoints, or `/tmp/` for workflow state.

## Checkpoint Protocol for Long Tasks

For tasks expected to require more than 15 turns (multi-document processing, full reviews, complex builds), the orchestrator MUST:

1. **Before delegating:** Create or identify a task entry in the `tasks` table with `status = 'in_progress'`.
2. **Instruct the agent** to persist progress to the DB after each major step:

> "This is a long task. After each major step, update the task checkpoint via SQL:
> ```sql
> UPDATE tasks SET description = json_object(
>   'step_completed', '{current_step}',
>   'next_step', '{next_step}',
>   'intermediate_data', '{summary_of_results}',
>   'files_touched', json_array('{path1}', '{path2}'),
>   'checkpoint_at', strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
> ) WHERE id = {task_id};
> ```
> Continue working after saving. Do NOT rely on conversation memory for state."

## Checkpoint Recovery

If an agent fails mid-task (error, context overflow, maxTurns reached):

1. The orchestrator MUST check for checkpoint data in the task:
   ```sql
   SELECT id, title, description FROM tasks WHERE status = 'in_progress';
   ```
2. If `description` contains valid JSON checkpoint data, the orchestrator MUST parse it and include it when relaunching the agent: "Resume from this checkpoint: [checkpoint contents]. Do NOT redo completed work."
3. If no checkpoint data exists, the orchestrator MUST inform the user that progress was lost and ask whether to restart from scratch or abandon.

## Context Preservation Rules

- Agents MUST persist important intermediate results to the database, NOT rely on conversation memory alone
- For document processing: read, extract, persist to DB, then move on. Do NOT keep raw document content in context.
- For multi-step workflows: save state to the `tasks.description` field after each major step. A new session MUST be able to resume from the last saved state.
- NEVER write checkpoint files to `/tmp/`, `Owners Inbox/`, or any other filesystem location. The database is the single source of truth.

## Mid-Session Context Preservation (MANDATORY)

Every 10-15 substantive interactions, the orchestrator MUST:

1. **Persist key learnings** to MemPalace via `palace.py add`
2. **Update task checkpoints** for any in-progress work
3. **Write agent observations** via `palace.py diary-write`
4. This is especially critical BEFORE delegating to agents that may consume many turns

MemPalace hooks handle auto-save every 15 messages and pre-compaction saves automatically.
