---
name: twin-update
description: "Detect new info about the owner from the session and update Owner Digital Twin files"
user-invocable: true
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep"]
---

# Owner Digital Twin Update

## When to Run

- **End of every session** — The orchestrator checks if new info about the owner surfaced
- **After adding user/feedback knowledge entries** — may contain preference changes
- **Manually** — when the owner shares personal/professional updates

## Step 1 — Gather Signal

Check recent knowledge entries for user-relevant info:
```sql
PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;
SELECT id, title, content, category, created_at FROM knowledge_entries
WHERE category IN ('user', 'feedback')
  AND is_archived = 0
  AND updated_at > COALESCE(
    (SELECT MAX(occurred_at) FROM activity_history WHERE action = 'twin_update_completed'),
    '2000-01-01'
  )
ORDER BY created_at DESC;
```

Also consider: what did the owner reveal during this session?
- New interests or projects mentioned?
- Preference corrections ("don't do X", "I prefer Y")?
- Career or business updates?
- New tools, technologies, or areas of focus?
- Changes in communication style preference?

If nothing new was detected, skip to Step 4 (log and exit).

## Step 2 — Classify and Route

Map each piece of new info to the correct file:

| Info Type | Target File |
|-----------|-------------|
| Career, role, company, education | `Owner/identidade.md` |
| Work style, communication, what to avoid/repeat | `Owner/preferencias.md` |
| New interests, areas of focus, hobbies, tech | `Owner/interesses.md` |
| Brand positioning, narrative, public persona | `Owner/marca-pessoal.md` |

## Step 3 — Update Files

For each file that needs updating:

1. **Read the current file** — always read before editing
2. **Check for duplicates** — don't add info that's already there
3. **Edit surgically** — add or modify only the relevant section
4. **Keep the format** — match existing style, concise, factual, PT-PT
5. **Never remove existing info** unless it's explicitly contradicted

Rules:
- Only update when genuinely new info surfaces
- Keep updates concise — 1-2 lines per new fact
- Use the same language and tone as existing content
- If uncertain whether something is worth adding, err on the side of NOT adding

## Step 4 — Log

Always log, even if no updates were made:

```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, metadata, occurred_at)
VALUES (
  1,
  'twin_update_completed',
  'owner_twin',
  CASE WHEN {updates_made} > 0
    THEN 'Digital Twin updated: ' || {files_changed}
    ELSE 'Digital Twin checked — no updates needed'
  END,
  json_object(
    'files_updated', json_array({list_of_files}),
    'entries_checked', {count},
    'updates_made', {updates_made}
  ),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
);
```

## Anti-Patterns

- Don't add trivial info ("the owner asked about ski boots" is NOT a twin update)
- Don't duplicate what's already in knowledge_entries — the twin is a curated summary, not a log
- Don't add speculative info — only confirmed facts or explicit preferences
- Don't rewrite entire files — surgical edits only
