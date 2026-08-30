---
name: db-health
description: "Quick database health audit: integrity, MemPalace tiers, FTS sync, backlog, failure patterns"
user-invocable: true
allowed-tools: Read Bash Glob
---

# Database Health Audit

Run all checks and produce a summary report.

The checks below run against the MemPalace schema (`drawers` and friends). If your
install still carries the older `knowledge_entries` layer, migrate first — do not
audit both, because two answers to "how many memories are there" is worse than one
wrong answer.

## Check 1 — Integrity

```sql
PRAGMA integrity_check;
PRAGMA foreign_key_check;
```

## Check 2 — MemPalace stats

```sql
SELECT
  (SELECT COUNT(*) FROM drawers)                          AS drawers_total,
  (SELECT COUNT(*) FROM drawers WHERE tier = 'hot')       AS hot,
  (SELECT COUNT(*) FROM drawers WHERE tier = 'warm')      AS warm,
  (SELECT COUNT(*) FROM drawers WHERE tier = 'cold')      AS cold,
  (SELECT COUNT(DISTINCT wing) FROM drawers)              AS wings,
  (SELECT COUNT(DISTINCT room) FROM drawers)              AS rooms,
  (SELECT COUNT(*) FROM kg_triples WHERE valid_to IS NULL) AS active_kg_facts,
  (SELECT COUNT(*) FROM diary_entries)                    AS diary_entries;
```

## Check 3 — Tier distribution

```bash
python3 scripts/memory_tiers.py --report
```

Non-destructive, safe to run any time. Flag if the hot tier grows out of
proportion (more than ~10% of the total): everything hot is loaded on every
session, so hot-tier growth is a direct tax on every conversation.

## Check 4 — FTS index sync

```sql
SELECT
  (SELECT COUNT(*) FROM drawers_fts) AS fts_indexed,
  (SELECT COUNT(*) FROM drawers)     AS drawers_rows;
```

The two should match. On drift, rebuild:

```sql
INSERT INTO drawers_fts(drawers_fts) VALUES('rebuild');
INSERT INTO drawers_fts(drawers_fts, rank) VALUES('integrity-check', 1);
```

If you also run a vector index, check it in the same breath — the `AFTER DELETE`
trigger keeps the FTS index honest but nothing keeps a vector table in sync
automatically.

## Check 5 — Task backlog

```sql
SELECT
  (SELECT COUNT(*) FROM tasks WHERE status='pending') AS pending_tasks,
  (SELECT COUNT(*) FROM tasks WHERE status='pending' AND title LIKE '[Kaizen]%') AS kaizen_backlog,
  (SELECT COUNT(*) FROM tasks WHERE status='in_progress' AND updated_at < datetime('now','-7 days')) AS stale_in_progress;
```

If you query the `description` column with `json_extract`, filter on
`json_valid(description) = 1` first — early rows tend to hold plain text, and
`json_extract` returns NULL for those without complaining.

## Check 6 — Knowledge graph health

```sql
SELECT
  (SELECT COUNT(*) FROM kg_triples WHERE valid_to IS NULL) AS active_facts,
  (SELECT COUNT(*) FROM kg_entities)                       AS entities;
```

## Check 7 — Agent failure patterns (24h)

```sql
SELECT json_extract(metadata, '$.agent') AS agent,
       COUNT(*) AS failures
FROM activity_history
WHERE action = 'agent_failure'
  AND occurred_at > datetime('now', '-24 hours')
GROUP BY agent
HAVING COUNT(*) >= 2;
```

## Check 8 — Cost telemetry

```sql
-- Recent rows with no computed cost: either the model is missing from
-- model_pricing, or the logging path is broken.
SELECT model, COUNT(*) AS rows_no_cost
FROM llm_calls
WHERE (cost_usd IS NULL OR cost_usd = 0)
  AND created_at > datetime('now', '-7 days')
GROUP BY model;
```

Any model appearing here with real volume needs a row in `model_pricing`.

## Check 9 — Procedural memory

```sql
SELECT COUNT(*) AS total_patterns,
       SUM(CASE WHEN success_rate >= 0.8 AND success_count >= 3 THEN 1 ELSE 0 END) AS reliable,
       SUM(CASE WHEN success_count <= 1 THEN 1 ELSE 0 END) AS never_reused,
       SUM(CASE WHEN dedup_key IS NULL THEN 1 ELSE 0 END) AS unreachable_orphans
FROM procedural_memory;
```

`never_reused` staying high while patterns keep being added means the capture side
works and the increment side does not. `unreachable_orphans` counts rows that
`proc-record` can never match again — every one of those is a pattern that can
never be promoted.

## Scoring

Start at 100. Deduct:

- -20: `integrity_check` fails
- -10: `foreign_key_check` fails
- -10: FTS out of sync with `drawers`
- -10: kaizen backlog over 30 pending (triage is behind)
- -5: stale `in_progress` tasks (older than 7 days)
- -5 per agent with 2+ failures in 24h
- -5: models with recent volume missing from `model_pricing`

## Report format

```
DB Health Score: XX/100
- Integrity: OK/FAIL
- Drawers: N (hot/warm/cold: N/N/N)
- FTS sync: OK/MISMATCH
- Backlog: N pending (N kaizen)
- KG: N active facts
- Agent failures (24h): N agents flagged
- Cost telemetry: OK / N models unpriced
- Procedural memory: N patterns (N reliable, N never reused, N orphans)
```

Flag to the user only if the score is below 80.
