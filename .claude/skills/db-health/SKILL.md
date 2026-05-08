---
name: db-health
description: "Quick database health audit: integrity, stale entries, missing summaries, orphan tags, failure patterns"
user-invocable: true
allowed-tools: ["Read", "Bash", "Glob"]
---

# Database Health Audit

Run all checks and produce a summary report.

## Check 1 -- Integrity

```sql
PRAGMA integrity_check;
PRAGMA foreign_key_check;
```

## Check 2 -- Context Health Dashboard

```sql
SELECT * FROM v_context_health;
```

## Check 3 -- Stale Knowledge

```sql
SELECT id, title, category, days_stale FROM v_stale_knowledge ORDER BY days_stale DESC LIMIT 20;
SELECT COUNT(*) as total_stale FROM v_stale_knowledge WHERE days_stale > 60;
```

## Check 4 -- Missing Summaries

```sql
SELECT id, title, category, content_length FROM v_missing_summaries;
SELECT COUNT(*) as total_missing FROM v_missing_summaries;
```

## Check 5 -- Hot Tier Size

```sql
SELECT COUNT(*) AS hot_tier_rows FROM v_context_bootstrap;
```

Target: < 40 rows. Warn if > 35.

## Check 6 -- Orphan Tags

```sql
SELECT t.id, t.name FROM tags t
WHERE NOT EXISTS (SELECT 1 FROM knowledge_entry_tags ket WHERE ket.tag_id = t.id);
```

## Check 7 -- Agent Failure Patterns (24h)

```sql
SELECT json_extract(metadata, '$.agent') AS agent,
       COUNT(*) AS recent_failures
FROM activity_history
WHERE action = 'agent_failure'
  AND occurred_at > datetime('now', '-24 hours')
GROUP BY json_extract(metadata, '$.agent')
HAVING COUNT(*) >= 2;
```

## Check 8 -- FTS5 Health

```sql
SELECT COUNT(*) as fts_rows FROM knowledge_fts;
SELECT COUNT(*) as active_entries FROM knowledge_entries WHERE is_archived = 0;
```

Both counts should match. If not, rebuild FTS index.

## Check 9 -- Procedural Memory

```sql
SELECT COUNT(*) as total_patterns,
       COUNT(CASE WHEN success_rate >= 0.7 THEN 1 END) as reliable_patterns,
       COUNT(CASE WHEN success_rate < 0.3 THEN 1 END) as unreliable_patterns
FROM procedural_memory;
```

## Scoring

Start at 100. Deduct:
- -20: integrity_check fails
- -10: foreign_key_check fails
- -5 per 10 stale entries (>60 days)
- -5 per 5 missing summaries
- -10: hot tier > 40 rows
- -3 per orphan tag
- -5 per agent with 2+ failures in 24h
- -5: FTS5 out of sync

## Report Format

```
DB Health Score: XX/100
- Integrity: OK/FAIL
- Stale entries (>60d): N
- Missing summaries: N
- Hot tier: N rows (target <40)
- Orphan tags: N
- Agent failures (24h): N agents flagged
- FTS5 sync: OK/MISMATCH
- Procedural memory: N patterns (N reliable)
```

Flag to {{OWNER}} only if score < 80.
