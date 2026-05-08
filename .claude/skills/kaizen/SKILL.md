---
name: kaizen
description: "Daily continuous improvement: system health, failure review, procedural learning, and 1-3 concrete improvement proposals"
user-invocable: true
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep"]
---

# Kaizen — Daily Continuous Improvement

## When to Run

- **Once per day** — at the start of the first session of the day
- **Triggered by `/session-start`** if not yet run today
- **Manually** — when {{OWNER}} requests a system review

## Check if Already Run Today

```sql
PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;
SELECT COUNT(*) as ran_today FROM activity_history
WHERE action = 'kaizen_completed'
  AND occurred_at > datetime('now', 'start of day');
```

If `ran_today > 0`, skip — already done today.

## Phase 1 — System Health (run /db-health logic)

```sql
-- Integrity
PRAGMA integrity_check;
PRAGMA foreign_key_check;

-- Context health
SELECT * FROM v_context_health;

-- Stale entries
SELECT COUNT(*) as stale_60d FROM v_stale_knowledge WHERE days_stale > 60;

-- Missing summaries
SELECT COUNT(*) as missing FROM v_missing_summaries;

-- Hot tier
SELECT COUNT(*) AS hot_tier_rows FROM v_context_bootstrap;

-- FTS5 sync check
SELECT
  (SELECT COUNT(*) FROM knowledge_fts) as fts_rows,
  (SELECT COUNT(*) FROM knowledge_entries WHERE is_archived = 0) as active_entries;

-- Orphan tags
SELECT COUNT(*) as orphans FROM tags t
WHERE NOT EXISTS (SELECT 1 FROM knowledge_entry_tags ket WHERE ket.tag_id = t.id);
```

Score the health (same rubric as /db-health).

## Phase 2 — Failure Review (last 24h)

```sql
-- Agent failures
SELECT json_extract(metadata, '$.agent') AS agent,
       json_extract(metadata, '$.error') AS error,
       summary,
       occurred_at
FROM activity_history
WHERE action = 'agent_failure'
  AND occurred_at > datetime('now', '-24 hours')
ORDER BY occurred_at DESC;

-- Failed LLM calls
SELECT agent_name, model, cost_usd, created_at
FROM llm_calls
WHERE cost_usd = 0
  AND created_at > datetime('now', '-24 hours');
```

For each failure pattern:
- What went wrong?
- Is it a recurring issue?
- What should change? (prompt adjustment, different agent, new skill, etc.)

## Phase 3 — Procedural Memory Review

```sql
-- Patterns with low success rate
SELECT trigger_pattern, action, success_count, failure_count, success_rate
FROM procedural_memory
WHERE success_rate < 0.5 AND (success_count + failure_count) >= 3
ORDER BY success_rate ASC;

-- New patterns since last kaizen
SELECT trigger_pattern, action, success_rate, created_at
FROM procedural_memory
WHERE created_at > COALESCE(
  (SELECT MAX(occurred_at) FROM activity_history WHERE action = 'kaizen_completed'),
  '2000-01-01'
);

-- High-performing patterns worth documenting
SELECT trigger_pattern, action, success_rate, success_count
FROM procedural_memory
WHERE success_rate >= 0.8 AND success_count >= 5
ORDER BY success_rate DESC;
```

## Phase 3.5 — KG Contradiction Detection

```sql
-- Find entities with duplicate active facts for the same predicate
SELECT subject, predicate, COUNT(*) as cnt,
       GROUP_CONCAT(object, ' | ') as conflicting_values
FROM kg_triples
WHERE valid_to IS NULL
GROUP BY subject, predicate
HAVING cnt > 1
ORDER BY cnt DESC;
```

For each contradiction found:
- Determine which fact is correct (check against source material or ask {{OWNER}})
- Invalidate the wrong one: `python3 scripts/palace.py kg-invalidate "subject" "predicate" "wrong_object"`
- If both are valid (e.g., multiple certifications), note it as non-conflicting

## Phase 3.6 — Memory Tier & Retrieval Health

```bash
# Tier distribution
python3 scripts/memory_tiers.py --report

# Run evaluation test set
python3 -c "
import json, struct, apsw, sqlite_vec
from sentence_transformers import SentenceTransformer
db = apsw.Connection('Database/team.db')
db.enableloadextension(True)
sqlite_vec.load(db)
model = SentenceTransformer('paraphrase-multilingual-mpnet-base-v2')
evals = json.load(open('scripts/eval_set.json'))
hits = 0
for e in evals:
    vec = model.encode(e['query'])
    results = db.execute('SELECT d.wing FROM drawers_vec v JOIN drawers d ON d.id = v.drawer_rowid WHERE v.embedding MATCH ? AND k = 5', (struct.pack('768f', *vec),)).fetchall()
    if e['expect_wing'] in [r[0] for r in results]:
        hits += 1
print(f'Retrieval precision@5: {hits}/{len(evals)} ({hits*100/len(evals):.0f}%)')
"
```

Flag if precision drops below 90%.

## Phase 4 — Infrastructure Check

Verify key system components:

```bash
# Skills exist and are well-formed
ls .claude/skills/*/SKILL.md

# Hooks are executable
ls -la .claude/hooks/*.sh

# Agent definitions exist
ls .claude/agents/*.md

# Owner Digital Twin files exist
ls Owner/

# Context pressure script works
python3 .claude/scripts/context-pressure.py --estimate 1000 --model opus
```

Check for:
- Skills that are outdated (referenced procedures changed in CLAUDE.md)
- Hooks that might need updating
- Agent definitions that are stale
- Owner Digital Twin last updated date

```sql
SELECT MAX(occurred_at) as last_twin_update FROM activity_history WHERE action = 'twin_update_completed';
```

If twin not updated in 7+ days, flag it.

## Phase 5 — Propose Improvements

Based on Phases 1-4, propose **1 to 3 concrete improvements**. Each must be:

- **Specific** — "Add a hook to block writes to /tmp" not "improve security"
- **Actionable** — clear next step (which agent, what change)
- **Justified** — why this matters (data from phases 1-4)

Categories of improvements:
- New skills for repetitive workflows detected
- Prompt adjustments for agents that keep failing
- Schema changes for missing data
- New hooks for guardrails gaps found
- Knowledge base hygiene items
- Process optimizations

**Present to {{OWNER}}. Never auto-implement.** Let him prioritize.

## Logging (MANDATORY)

```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, metadata, occurred_at)
VALUES (
  1,
  'kaizen_completed',
  'system',
  'Kaizen daily review: health score X/100, Y failures reviewed, Z improvements proposed',
  json_object(
    'health_score', ?,
    'failures_24h', ?,
    'improvements_proposed', ?,
    'twin_days_stale', ?,
    'procedural_patterns', ?
  ),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
);
```

## Output Format

```
## Kaizen Report — {date}

### System Health: XX/100
- [OK/WARN] Integrity
- [OK/WARN] Stale entries: N (>60d)
- [OK/WARN] Missing summaries: N
- [OK/WARN] Hot tier: N rows
- [OK/WARN] FTS5 sync
- [OK/WARN] Orphan tags: N

### Failures (24h)
- {count} failures, {patterns found}
- Most affected: {agent_name} ({N} failures)

### Procedural Memory
- {N} total patterns, {N} reliable (>80%), {N} unreliable (<50%)
- New since last kaizen: {N}

### Proposed Improvements
1. **{title}** — {description}. {justification}.
2. **{title}** — {description}. {justification}.

### Digital Twin
- Last updated: {date} ({N} days ago)
```
