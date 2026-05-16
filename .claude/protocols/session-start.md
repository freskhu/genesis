# Session Start Protocol (MANDATORY)

**Trigger:** Start of every conversation (the orchestrator's first message in a new session).

At the **start of every conversation**, the orchestrator must:

**Step 0 — Regenerate Memory Hot:**
```bash
python3 scripts/generate_memory_hot.py
```
Then read `.claude/memory-hot.md` — this is the session briefing with current state.

**Step 1 — Inbox Check:**
1. List files in `Team Inbox/`
2. Query `processed_inbox_files` table in `Database/team.db` to see which files have already been processed
3. If any file in `Team Inbox/` is NOT in the processed list, flag it to the user immediately and suggest what to do with it
4. After processing a file (with the user's approval), mark it as processed in the database via Lena

**Step 2 — Pending Tasks Check:**
1. Query `SELECT * FROM v_open_tasks;` in `Database/team.db`
2. If there are any open tasks (pending, in_progress, or blocked), present them to the user: "You have X pending tasks: [list]. Want to pick any up?"
3. Let the user decide what to pick up — don't assume

**Step 2.5 — Kaizen Backlog Surface (MANDATORY when applicable):**
1. Query stale kaizen proposals (kaizen inserts proposals with `[Kaizen]` prefix in title):
   ```sql
   SELECT id, title, created_at, julianday('now') - julianday(created_at) AS days_pending
   FROM tasks
   WHERE status = 'pending' AND title LIKE '[Kaizen]%'
     AND julianday('now') - julianday(created_at) > 2
   ORDER BY created_at ASC;
   ```
2. If 3 or more proposals are pending >48h, surface them prominently to the user at session start (separate from regular pending tasks): "There are X kaizen proposals pending more than 2 days: [list]. Tackle any?"
3. Backlog policy: proposals stay `pending` indefinitely (never auto-expire). Only the user closes/drops them.
4. Reason for the rule: kaizen surfaces value but without a feedback loop, proposals accumulate unread.

**Step 3 — Session Tracking:**

Log the session start:
```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, occurred_at)
VALUES (1, 'session_start', 'system', 'Session started', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
```

**Step 4 — Kaizen Check (Daily Continuous Improvement):**
1. Check if `/kaizen` already ran today:
   ```sql
   SELECT COUNT(*) as ran_today FROM activity_history
   WHERE action = 'kaizen_completed' AND occurred_at > datetime('now', 'start of day');
   ```
2. If `ran_today = 0`, run `/kaizen` — system health, failure review, improvement proposals
3. Present the kaizen report to the user

**All four steps are mandatory. None can be skipped.**
