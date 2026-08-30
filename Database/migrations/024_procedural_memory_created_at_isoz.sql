-- 024: normalise procedural_memory.created_at to ISO-8601 with a Z suffix.
--
-- The column accumulated two formats side by side: "YYYY-MM-DD HH:MM:SS" from the
-- column DEFAULT datetime('now'), and "YYYY-MM-DDTHH:MM:SSZ" from callers writing
-- strftime. Lexicographic comparisons silently dropped rows, because ' ' sorts
-- before 'T' -- every "since date X" query was quietly reading a subset.
--
-- Mixed timestamp formats in one column are invisible until a range query lies to
-- you. Normalise on write, and normalise on both sides of any comparison.
--
-- Note: the column DEFAULT stays datetime('now') (space format) -- changing it
-- requires a table rebuild. Consumers should compare via datetime() on both sides.
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;

UPDATE procedural_memory
SET created_at = strftime('%Y-%m-%dT%H:%M:%SZ', datetime(created_at))
WHERE created_at IS NOT NULL
  AND created_at NOT LIKE '____-__-__T__:__:__Z';

INSERT INTO schema_versions (version, name)
VALUES (24, '024_procedural_memory_created_at_isoz');
