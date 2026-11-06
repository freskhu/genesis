-- Rollback of migration 027 (spec_criteria).
-- Drops the table, its index and its triggers, and the schema_versions row.
-- The criteria state is lost; the spec files keep their text. Take a backup first.
--
-- Apply: sqlite3 Database/team.db < Database/migrations/027_rollback_spec_criteria.sql

BEGIN;

DROP TRIGGER IF EXISTS trg_spec_criteria_born_fail;
DROP TRIGGER IF EXISTS trg_spec_criteria_transition;
DROP TRIGGER IF EXISTS trg_spec_criteria_verifier;
DROP TRIGGER IF EXISTS trg_spec_criteria_immutable;
DROP TRIGGER IF EXISTS trg_spec_criteria_author_fixed;
DROP TRIGGER IF EXISTS trg_spec_criteria_no_delete;
DROP INDEX IF EXISTS idx_spec_criteria_spec;
DROP TABLE IF EXISTS spec_criteria;
DELETE FROM schema_versions WHERE version = 27;

COMMIT;
