-- Migration 026 -- v_palace_stats: the view palace.py status and generate_memory_hot.py read
--
-- Closes the known install gap: both scripts read v_palace_stats, and schema.sql did not
-- create it, so `palace.py status` failed on a fresh install. The vector table
-- (drawers_vec) needs the sqlite-vec extension, which the sqlite3 CLI does not load; it is
-- created by scripts/palace.py on first connection instead.
--
-- Column order is part of the contract (both scripts read by position):
--   0 total_drawers, 1 hot, 2 warm, 3 cold, 4 wings, 5 rooms, 6 active_kg_facts,
--   7 diary_entries
--
-- Apply:    sqlite3 Database/team.db < Database/migrations/026_palace_stats_view.sql
-- Rollback: DROP the view and delete schema_versions row 26.

BEGIN;

DROP VIEW IF EXISTS v_palace_stats;
CREATE VIEW v_palace_stats AS
SELECT
    (SELECT COUNT(*) FROM drawers)                          AS total_drawers,
    (SELECT COUNT(*) FROM drawers WHERE tier = 'hot')       AS hot_drawers,
    (SELECT COUNT(*) FROM drawers WHERE tier = 'warm')      AS warm_drawers,
    (SELECT COUNT(*) FROM drawers WHERE tier = 'cold')      AS cold_drawers,
    (SELECT COUNT(DISTINCT wing) FROM drawers)              AS wings,
    (SELECT COUNT(DISTINCT room) FROM drawers)              AS rooms,
    (SELECT COUNT(*) FROM kg_triples WHERE valid_to IS NULL) AS active_kg_facts,
    (SELECT COUNT(*) FROM diary_entries)                    AS diary_entries;

INSERT INTO schema_versions (version, name) VALUES (26, 'palace_stats_view');

COMMIT;
