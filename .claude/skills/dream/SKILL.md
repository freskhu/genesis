---
name: dream
description: "Auto-dream protocol: 4-phase knowledge base maintenance cycle (orient, gather, consolidate, prune)"
user-invocable: true
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep"]
---

# Auto-Dream Protocol

Delegate to your Knowledge Architect. 4 phases, all mandatory.

## Phase 1 -- ORIENT

Read the health dashboard:

```sql
-- 1a. Health dashboard
SELECT * FROM v_context_health;
-- 1b. Stale entries
SELECT id, title, category, days_stale FROM v_stale_knowledge;
-- 1c. Missing summaries
SELECT id, title, category, content_length FROM v_missing_summaries;
-- 1d. Hot tier size (target: < 40 rows)
SELECT COUNT(*) AS hot_tier_rows FROM v_context_bootstrap;
```

**Decision gate:** If all green (0 stale, 0 missing summaries, hot tier < 35), skip to Phase 4.

## Phase 2 -- GATHER SIGNAL

```sql
-- 2a. Recently added entries since last dream
SELECT ke.id, ke.title, ke.category,
  (SELECT COUNT(*) FROM knowledge_entry_tags ket WHERE ket.knowledge_entry_id = ke.id) AS tag_count
FROM knowledge_entries ke
WHERE ke.is_archived = 0
  AND ke.created_at > COALESCE(
    (SELECT MAX(occurred_at) FROM activity_history WHERE action = 'auto_dream_completed'),
    '2000-01-01'
  )
ORDER BY ke.created_at DESC;

-- 2b. Entries with no tags
SELECT id, title, category FROM knowledge_entries
WHERE is_archived = 0
  AND NOT EXISTS (SELECT 1 FROM knowledge_entry_tags ket WHERE ket.knowledge_entry_id = id);

-- 2c. Category consistency
SELECT DISTINCT category, COUNT(*) FROM knowledge_entries
WHERE is_archived = 0
  AND category NOT IN ('user', 'feedback', 'project', 'reference', 'strategy', 'technical')
GROUP BY category;

-- 2d. Duplicate detection
SELECT a.id AS id_a, b.id AS id_b, a.title AS title_a, b.title AS title_b
FROM knowledge_entries a
JOIN knowledge_entries b ON a.id < b.id
WHERE a.is_archived = 0 AND b.is_archived = 0
  AND a.category = b.category
  AND (a.title LIKE '%' || b.title || '%' OR b.title LIKE '%' || a.title || '%');
```

## Phase 3 -- CONSOLIDATE

- Write missing summaries (1-line, "What would I use this entry for?")
- Fix non-standard categories
- Add missing tags (2-4 per entry from existing pool)
- Merge duplicates: keep richer content, archive the other, move unique tags

## Phase 4 -- PRUNE

| Condition | Action |
|-----------|--------|
| Stale > 60 days AND category = `project` | Archive |
| Stale > 90 days AND category NOT IN (`user`, `reference`) | Flag for {{OWNER}} review |
| Stale > 30 days AND category = `technical` AND title contains "Status" | Archive |
| Orphan tags (no entries) | Delete |

Never auto-archive: `user`, `reference`, `strategy` entries (while {{COURSE}} active).

```sql
DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM knowledge_entry_tags);
```

## Logging (MANDATORY)

```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, metadata, occurred_at)
VALUES (
  11, 'auto_dream_completed', 'knowledge_entries',
  'Auto-dream cycle completed: X stale reviewed, Y summaries written, Z entries archived',
  json_object('stale_reviewed', ?, 'summaries_written', ?, 'entries_archived', ?,
    'tags_cleaned', ?, 'hot_tier_rows', ?, 'total_active', ?),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
);
```

## Health Check (MANDATORY after logging)

```sql
SELECT * FROM v_context_health;
```

Report to {{OWNER}} ONLY if thresholds breached:
- `stale_entries_60d > 10`
- `missing_summaries > 5`
- `hot_tier_rows > 40`

If all green: "Knowledge base saudavel, dream cycle completo."
