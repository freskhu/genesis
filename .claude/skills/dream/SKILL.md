---
name: dream
description: "Auto-dream protocol: 4-phase MemPalace maintenance cycle (orient, gather, consolidate, prune) over drawers + FTS + KG + diary"
user-invocable: true
allowed-tools: Read Write Edit Bash Glob Grep
---

# Auto-Dream Protocol

Delegate to your Knowledge Architect. Four phases, all mandatory.

**Substrate:** MemPalace in `Database/team.db` — `drawers` (content), `drawers_fts`
(FTS5 external-content index), `kg_entities` / `kg_triples` (knowledge graph),
`diary_entries`. If you run a vector index alongside, it is part of the substrate
too and every consistency check below applies to it as well.

**SQL access:** the `sqlite3` CLI does not load the vector extension. For anything
touching the vector table, use Python with `apsw` plus `sqlite_vec.load(db)` — the
same pattern as `scripts/palace.py::connect()`. PRAGMAs on every connection:
`foreign_keys=ON`, `journal_mode=WAL`, `busy_timeout=5000`.

## Golden rule: no destructive action without sign-off

The dream cycle NEVER deletes, merges or archives drawers, triples or diary
entries on its own initiative. Phases 1 and 2 are read-only. Phase 3 performs
only additive or corrective non-destructive writes (room/hall reclassification,
tier moves via `memory_tiers.py`). Phase 4 produces a LIST of candidates and takes
it to the user for approval. Deletions execute only after an explicit OK, and
always with a fresh backup of `team.db` first — taken with `VACUUM INTO`, never
by copying the file while WAL mode is on.

A maintenance job with delete permission and no human in the loop is one bad
heuristic away from erasing the memory it exists to protect.

## Phase 1 — ORIENT

General state:

```bash
python3 scripts/palace.py status          # counts by wing/room/tier
python3 scripts/palace.py kg-stats        # KG health (staleness, orphans)
python3 scripts/memory_tiers.py --report  # hot/warm/cold distribution (non-destructive)
```

Structural consistency:

```sql
-- 1a. FTS5 integrity (external-content index; errors out if it has drifted)
INSERT INTO drawers_fts(drawers_fts, rank) VALUES('integrity-check', 1);

-- 1b. Index population vs source rows (should match)
SELECT (SELECT COUNT(*) FROM drawers_fts) AS fts_rows,
       (SELECT COUNT(*) FROM drawers)     AS drawer_rows;

-- 1c. File integrity
PRAGMA integrity_check;
```

**Decision gate:** if everything is green (indexes in sync, FTS ok, integrity ok,
no anomalies in status), skip to Phase 4.

**FTS note:** the `drawers_fts_ad` (AFTER DELETE) trigger does not reliably clean
an external-content index. After any deletion from `drawers`, always run
`INSERT INTO drawers_fts(drawers_fts) VALUES('rebuild');`. A vector table has no
trigger at all — its rows must be deleted by hand.

## Phase 2 — GATHER SIGNAL

```sql
-- 2a. Drawers added since the last dream
SELECT id, wing, room, hall, substr(content,1,80)
FROM drawers
WHERE filed_at > COALESCE(
  (SELECT MAX(occurred_at) FROM activity_history WHERE action = 'auto_dream_completed'),
  '2000-01-01')
ORDER BY filed_at DESC;

-- 2b. Catch-alls and rooms outside the taxonomy (see the room table in CLAUDE.md)
SELECT room, COUNT(*) FROM drawers
WHERE room NOT IN ('identity','decisions','architecture','research','reference',
  'protocols','content','configuration','code','cases','reports','operations',
  'preferences','archive')
GROUP BY room;

-- 2c. Halls outside the taxonomy
SELECT hall, COUNT(*) FROM drawers
WHERE hall NOT IN ('hall_facts','hall_events','hall_discoveries','hall_preferences','hall_advice')
GROUP BY hall;

-- 2d. Exact full-field duplicates
SELECT content, wing, room, hall, COUNT(*) n, GROUP_CONCAT(id) ids
FROM drawers GROUP BY content, wing, room, hall HAVING COUNT(*) > 1;

-- 2e. Cross-wing duplicates — could be an intentional tunnel OR double ingestion.
--     Check source_file before concluding anything.
SELECT content, COUNT(DISTINCT wing) wings, GROUP_CONCAT(id) ids
FROM drawers GROUP BY content HAVING COUNT(DISTINCT wing) > 1;
```

Supporting signal:

```bash
python3 scripts/palace.py diary-read "<orchestrator>" --last 10   # recurring patterns
python3 scripts/palace.py kg-stats                                 # triples due for invalidation
```

## Phase 3 — CONSOLIDATE (non-destructive writes only)

- Reclassify drawers sitting in out-of-taxonomy rooms/halls into the correct
  semantic room and hall (UPDATE, never DELETE).
- Promote or demote tiers via `scripts/memory_tiers.py --execute`. It respects the
  structural rules: `identity` / `preferences` / `protocols` / `configuration`
  rooms, the `hall_preferences` hall and the owner wing stay hot;
  `reference` / `architecture` / `cases` / `code` stay warm even when old.
- KG: `palace.py kg-add` for newly detected facts, `palace.py kg-invalidate` for
  relationships that no longer hold. Invalidation is soft, so it is safe here.
- After any UPDATE on `drawers`, the `drawers_fts_au` trigger keeps the FTS index
  current. An embedding does NOT update itself — if the content changed, re-embed
  it, the same way `palace.py add` does.

## Phase 4 — PRUNE (propose, do not execute)

Compile the candidate list and put it to the user for sign-off:

| Candidate | Criterion |
|-----------|-----------|
| Exact full-field duplicates (2d) | Keep `MIN(id)`, propose deleting the rest |
| Cross-wing duplicates from double ingestion (2e) | Pick the canonical wing per content type; propose only where `source_file` proves double ingestion; leave ambiguous ones alone |
| Drawers in `archive` for more than 90 days with no hits | Propose deletion or export to a file |
| Invalid or contradictory KG triples | Propose `kg-invalidate` |

Never propose for pruning: the owner wing, the `identity` and `preferences` rooms,
`hall_preferences`, or any content tied to an active project.

**After approved deletions execute (mandatory checklist):**

1. Delete the corresponding vector rows for every deleted drawer (no trigger does this)
2. `INSERT INTO drawers_fts(drawers_fts) VALUES('rebuild');`
3. `INSERT INTO drawers_fts(drawers_fts, rank) VALUES('integrity-check', 1);`
4. `PRAGMA integrity_check;`
5. A test `palace.py search` (hybrid and keyword) to confirm retrieval still works

Step 5 is the one people skip. The first four confirm the database is structurally
fine; only the fifth confirms the thing the database exists to do still works.

## Logging (MANDATORY)

```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, metadata, occurred_at)
VALUES (
  (SELECT id FROM team_members WHERE name = '<knowledge architect>'),
  'auto_dream_completed', 'drawers',
  'Auto-dream cycle: X drawers reviewed, Y reclassified, Z prune candidates proposed',
  json_object('drawers_total', ?, 'reclassified', ?, 'prune_candidates', ?,
    'kg_triples_flagged', ?, 'fts_ok', ?, 'vec_synced', ?),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
);
```

Plus a diary entry:
`palace.py diary-write "<agent>" "SESSION:YYYY-MM-DD|dream.cycle|..." --topic "dream"`.

## Health check (MANDATORY after logging)

```bash
python3 scripts/palace.py status
python3 scripts/memory_tiers.py --report
```

Report to the user ONLY if a threshold was breached:

- Exact duplicates > 0
- Indexes out of sync, or the FTS integrity check failed
- More than 20 drawers in out-of-taxonomy rooms/halls
- Prune candidates awaiting sign-off

If everything is green: "MemPalace healthy, dream cycle complete."
