-- Migration 025 -- drawers_fts: use the FTS5 'delete' command in the sync triggers
--
-- The defect: drawers_fts is an external-content FTS5 table (content='drawers'). The
-- original update and delete triggers removed the old row with a plain
--     DELETE FROM drawers_fts WHERE rowid = old.id;
-- On an external-content table that does not remove the old TOKENS from the index: FTS5
-- needs the old column values to know which tokens to drop, and a plain DELETE does not
-- give them. After rewriting a drawer, the old words stayed searchable with MATCH and
-- pointed at the rewritten drawer. That matters most when a drawer is rewritten precisely
-- to remove sensitive content (.claude/rules/health-data-boundary.md, section 4).
--
-- Why a row count never caught it: the row count of an external-content FTS table is
-- derived from the content table, so COUNT(*) is always equal, with or without the
-- defect. The defect leaves orphan tokens, not orphan rows. scripts/palace_audit.py
-- checks for it by rebuilding the index in memory and comparing vocabularies.
--
-- The fix: the FTS5 documented pattern, INSERT ... VALUES('delete', old.rowid, old.cols).
-- The update trigger fires only when an indexed column changes.
--
-- Apply:    sqlite3 Database/team.db < Database/migrations/025_drawers_fts_delete_triggers.sql
-- Verify:   python3 scripts/palace_audit.py   (fts_desync must be 0)
-- Rollback: recreate the two triggers as in Database/schema.sql (not recommended: it
--           reintroduces the defect).

BEGIN;

DROP TRIGGER IF EXISTS drawers_fts_ad;
CREATE TRIGGER drawers_fts_ad AFTER DELETE ON drawers BEGIN
    INSERT INTO drawers_fts(drawers_fts, rowid, content, wing, room, hall, source_file)
    VALUES ('delete', old.id, old.content, old.wing, old.room, old.hall, old.source_file);
END;

DROP TRIGGER IF EXISTS drawers_fts_au;
CREATE TRIGGER drawers_fts_au
AFTER UPDATE OF content, wing, room, hall, source_file ON drawers BEGIN
    INSERT INTO drawers_fts(drawers_fts, rowid, content, wing, room, hall, source_file)
    VALUES ('delete', old.id, old.content, old.wing, old.room, old.hall, old.source_file);
    INSERT INTO drawers_fts(rowid, content, wing, room, hall, source_file)
    VALUES (new.id, new.content, new.wing, new.room, new.hall, new.source_file);
END;

INSERT INTO schema_versions (version, name) VALUES (25, 'drawers_fts_delete_triggers');

COMMIT;

-- Repair any orphan tokens left by the old triggers. Idempotent; cheap on a small palace.
INSERT INTO drawers_fts(drawers_fts) VALUES('rebuild');
