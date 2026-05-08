---
name: session-start
description: "Run the mandatory 3-step session start protocol: inbox check, pending tasks, session tracking + dream check"
user-invocable: true
allowed-tools: ["Read", "Bash", "Glob", "Grep"]
---

# Session Start Protocol

Run all 3 steps in order. None can be skipped.

## Step 1 -- Inbox Check

1. List files in `Team Inbox/`:
```bash
ls -la "Team Inbox/"
```

2. Check which files are already processed:
```sql
SELECT filename, processed_at FROM processed_inbox_files;
```

3. If any file in `Team Inbox/` is NOT in the processed list, flag it to {{OWNER}}:
   - Show the filename and suggest what to do (index in knowledge base, assign to team member, file for reference)
   - Wait for {{OWNER}}'s decision before processing

4. After processing (with {{OWNER}}'s approval), mark as processed via Lena:
```sql
INSERT INTO processed_inbox_files (filename, processed_at) VALUES (?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
```

## Step 2 -- Pending Tasks Check

1. Query open tasks:
```sql
SELECT * FROM v_open_tasks;
```

2. If there are open tasks (pending, in_progress, or blocked):
   - Present to {{OWNER}}: "Tens X tarefas pendentes: [list]. Queres avancar com alguma?"
   - Let {{OWNER}} decide -- don't assume

3. Check stale knowledge:
```sql
SELECT count(*) as stale_count FROM v_stale_knowledge WHERE days_stale > 60;
```
   - If stale_count > 5, flag to {{OWNER}}

## Step 3 -- Session Tracking & Dream Check

1. Log session start:
```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, occurred_at)
VALUES (1, 'session_start', 'system', 'Session started', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
```

2. Check if dream cycle is due:
```sql
SELECT COUNT(*) AS sessions_since_dream FROM activity_history
WHERE action = 'session_start' AND occurred_at > (
  SELECT COALESCE(MAX(occurred_at), '2000-01-01') FROM activity_history WHERE action = 'auto_dream_completed'
);
```

3. Check time since last dream:
```sql
SELECT COALESCE(MAX(occurred_at), '2000-01-01') AS last_dream FROM activity_history WHERE action = 'auto_dream_completed';
```

4. If `sessions_since_dream >= 5` OR last dream > 24h ago:
   - Delegate to your Knowledge Architect: "Knowledge Architect, corre o auto-dream protocol."
   - Use `/dream` skill

5. If neither condition met, proceed normally.

## Step 4 -- Kaizen Check (Daily Continuous Improvement)

Check if kaizen already ran today:
```sql
SELECT COUNT(*) as ran_today FROM activity_history
WHERE action = 'kaizen_completed'
  AND occurred_at > datetime('now', 'start of day');
```

If `ran_today = 0`:
- Run `/kaizen` — daily system health + failure review + improvement proposals
- Present the kaizen report to {{OWNER}}

If already ran today, skip.

## Session End Reminder

At the end of every session, the orchestrator MUST:
1. Run `/twin-update` — check if new info about the owner surfaced and update Owner Digital Twin
2. This is not optional. The twin only stays useful if it's kept current.
