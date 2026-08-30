# Session Start Protocol (MANDATORY)

**Trigger:** Run at the start of every session by invoking `/session-start`.
Manual trigger by the user — there is deliberately NO auto-firing hook.

An earlier `UserPromptSubmit` gate was removed: it fired in *every* Claude Code
window opened anywhere inside the project tree, including unrelated ones, and
broke them — the relative path failed to resolve in sub-`cwd` sessions, and the
context injection broke windows running models that reject a `system` role. A
session-start hook is a tempting piece of automation with a wide blast radius;
the end side keeps its `force-session-end.sh` Stop hook, which is scoped to the
close of a session and is therefore safe. The start side is manual by choice.

**Single source of truth:** this file. The `/session-start` skill is a thin
wrapper that points here. Do not duplicate the logic in the skill — two copies
of a protocol drift, and the copy the agent happens to read wins.

**Always-on:** the full ritual runs on every session, regardless of weight. Two
things were deliberately moved OUT of the start path:

- **A full `/kaizen` run** → belongs on a schedule, not on the start path. At
  start we only *surface* the kaizen backlog (Step 3, a fast query). A review
  that runs on every session start turns into a tax on every session.
- **Any network fetch** (for example the Genesis forum) → on-demand only. No
  session should have to wait on the network before it can begin.

Run Steps 0–5 in order before addressing the user's request.

---

**Step 0 — Regenerate & read Memory Hot:**
```bash
python3 scripts/generate_memory_hot.py
```
Then read `.claude/memory-hot.md` — the session briefing with current state
(owner facts, active projects, pending tasks, unprocessed inbox, recent
activity, decisions, team, learned patterns, memory stats).

**Step 1 — Inbox Check:**
1. List files in `Team Inbox/`.
2. Query `processed_inbox_files` in `Database/team.db` for what is already done.
3. Any file NOT in the processed list → flag it to the user and suggest an
   action (index in MemPalace, assign to a team member, file for reference).
4. After processing, with the user's approval, mark it processed via Lena.

**Step 2 — Pending Tasks Check:**
```sql
SELECT * FROM v_open_tasks;
```
If there are open tasks (pending, in_progress, blocked), present them: "You have
X pending tasks: [list]. Want to pick any up?" Let the user decide — do not
assume.

**Step 3 — Kaizen Backlog Surface (when applicable):**
```sql
SELECT id, title, created_at, julianday('now') - julianday(created_at) AS days_pending
FROM tasks
WHERE status = 'pending' AND title LIKE '[Kaizen]%'
  AND julianday('now') - julianday(created_at) > 2
ORDER BY created_at ASC;
```
If 3 or more proposals have been pending for more than 48h, surface them
separately from the regular task list: "There are X kaizen proposals pending more
than 2 days: [list]. Tackle any?"

Proposals stay `pending` indefinitely — they never auto-expire, and only the user
closes or drops them. Surfaced at start and again at end: two nudges per session,
which is a reminder rather than nagging.

*If you move the kaizen backlog to an issue tracker or a project board, replace
this query with the equivalent listing and keep the rule.* Network or CLI failure
here → skip silently. A backlog reminder must never be able to block a session.

**Step 4 — Dream Check (knowledge maintenance):**
```sql
-- sessions since the last dream
SELECT COUNT(*) AS sessions_since_dream FROM activity_history
WHERE action = 'session_start' AND occurred_at > (
  SELECT COALESCE(MAX(occurred_at), '2000-01-01') FROM activity_history WHERE action = 'auto_dream_completed'
);
-- time since the last dream
SELECT COALESCE(MAX(occurred_at), '2000-01-01') AS last_dream FROM activity_history WHERE action = 'auto_dream_completed';
```
If `sessions_since_dream >= 5` OR the last dream was more than 24h ago → run the
`/dream` skill. Otherwise proceed.

**Step 5 — Session Tracking:**
```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, occurred_at)
VALUES (1, 'session_start', 'system', 'Session started', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
```
This row also feeds the dream-check counter in Step 4 and the end-side
memory-hot staleness check. Logging it reliably is what fixes the classic
start/end asymmetry, where sessions end far more often than they are recorded as
having started, and every counter downstream reads nonsense as a result.

---

**All steps run on every session.** If a step has nothing to surface (empty
inbox, no open tasks, no stale kaizen, dream not due), say so in one line and
move on — do not invent work.
