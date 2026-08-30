-- 013_procedural_dedup_key.sql
-- Purpose: fix the procedural_memory increment loop.
--
-- ROOT CAUSE
--   procedural_memory had NO matching/dedup key. The protocol asked the caller
--   to craft an INSERT for a new pattern and a separate UPDATE for a reused one,
--   choosing by hand which branch to run. In practice every capture ran the
--   INSERT branch, so each repeated pattern produced a brand-new row and
--   success_count never climbed past 1. There was no stored identity a write
--   path could match against, and the free-text (trigger_pattern, action) pair
--   never collides exactly.
--
-- FIX
--   Give every pattern a stable identity: dedup_key = normalised trigger_pattern
--   (lowercased, leading/trailing/collapsed whitespace removed). A UNIQUE index
--   on dedup_key lets a single UPSERT path increment on repeat instead of
--   inserting. palace.py gains a `proc-record` command that performs the UPSERT.
--
-- IMPACT
--   - New column procedural_memory.dedup_key (nullable, backfilled here).
--   - New UNIQUE index idx_procedural_memory_dedup.
--   - No data loss; existing rows keep their counters. Verify the backfill is
--     collision-free on YOUR data before applying: two rows whose trigger_pattern
--     normalises to the same string will fail the UNIQUE index.
--     SELECT lower(trim(trigger_pattern)) k, COUNT(*) FROM procedural_memory
--     GROUP BY k HAVING COUNT(*) > 1;
--   - Increment policy stays "match on trigger_pattern identity"; action text may
--     evolve without forking the pattern.
--
-- ROLLBACK
--   DROP INDEX idx_procedural_memory_dedup;  -- column can stay (harmless) or be
--   rebuilt-out via table copy if a hard revert is required.

-- 1. Add the dedup key column (nullable so ALTER succeeds on the existing table).
ALTER TABLE procedural_memory ADD COLUMN dedup_key TEXT;

-- 2. Backfill: normalise trigger_pattern.
--    lower + trim handles edges; the nested replace() collapses runs of up to
--    8 spaces to a single space (SQLite has no regex). Adequate for the captured
--    free-text triggers, none of which contain tabs/newlines.
UPDATE procedural_memory
SET dedup_key = lower(trim(
        replace(replace(replace(replace(trigger_pattern,
            '        ', ' '),
            '    ', ' '),
            '   ', ' '),
            '  ', ' ')
));

-- 3. Enforce one row per pattern identity. UNIQUE so UPSERT (ON CONFLICT) works.
CREATE UNIQUE INDEX IF NOT EXISTS idx_procedural_memory_dedup
    ON procedural_memory(dedup_key);

-- 4. Record the migration.
INSERT INTO schema_versions (version, name)
VALUES (13, '013_procedural_dedup_key');
