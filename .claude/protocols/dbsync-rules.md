# DB-Sync Rules (MANDATORY — NO EXCEPTIONS)

**Trigger:** End of any workflow (hire, inbox processing, task work, deliverable production).

The database MUST be updated as the **final step** of every workflow. No task is complete until the DB reflects the change. The orchestrator is responsible for enforcing this by delegating to Lena as the last step when needed.

**Hiring workflow → DB sync:**
- When Sarah creates a new team member, the orchestrator MUST delegate to Lena to INSERT the new member into `team_members` table with all fields (name, role, status, profile_path, agent_path, joined_at)
- This happens BEFORE the hire is reported as complete to the user

**Inbox processing → DB sync:**
- When a Team Inbox file is processed, it MUST be marked in `processed_inbox_files`
- When content needs indexing, add it to MemPalace via `palace.py add`

**Task tracking → DB sync:**
- When work is assigned or completed, log it in `activity_history`
- Significant tasks should be tracked in the `tasks` table

**Deliverables → DB sync:**
- When a team member produces a deliverable in `Owners Inbox/`, log it in `deliverables` table

**General rule:** If it happened and it matters, it goes in the database. When in doubt, write to the DB.
