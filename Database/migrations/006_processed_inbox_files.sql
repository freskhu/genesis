-- Migration 006: processed_inbox_files
-- Tracks which files in Team Inbox/ have been detected and processed by the orchestrator.
-- This gives the team visibility into inbox handling and prevents re-processing.

CREATE TABLE processed_inbox_files (
    id              INTEGER PRIMARY KEY,
    file_path       TEXT    NOT NULL UNIQUE,       -- full relative path from project root (e.g. "Team Inbox/project-context-prompt.md")
    filename        TEXT    NOT NULL,               -- just the filename for quick display
    status          TEXT    NOT NULL DEFAULT 'detected'
                        CHECK (status IN ('detected', 'processing', 'processed', 'skipped', 'error')),
    detected_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),  -- when the file was first noticed
    processed_at    TEXT,                           -- when processing completed (NULL until done)
    processed_by    INTEGER REFERENCES team_members(id) ON DELETE RESTRICT,  -- who processed it
    notes           TEXT,                           -- free-form notes about what was done
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Index on status for filtering unprocessed files quickly
CREATE INDEX idx_processed_inbox_files_status ON processed_inbox_files (status);

-- Auto-update trigger for updated_at
CREATE TRIGGER trg_processed_inbox_files_updated_at
    AFTER UPDATE ON processed_inbox_files
    FOR EACH ROW
BEGIN
    UPDATE processed_inbox_files SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = NEW.id;
END;

-- Activity history trigger on INSERT
CREATE TRIGGER trg_activity_processed_inbox_files_insert
    AFTER INSERT ON processed_inbox_files
    FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary)
    VALUES (
        COALESCE(NEW.processed_by, 1),
        'detected_inbox_file',
        'processed_inbox_files',
        NEW.id,
        'Detected inbox file: ' || NEW.filename
    );
END;

-- Activity history trigger on UPDATE (guarded against double-fire from updated_at trigger)
CREATE TRIGGER trg_activity_processed_inbox_files_update
    AFTER UPDATE ON processed_inbox_files
    FOR EACH ROW
    WHEN OLD.updated_at != NEW.updated_at
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary)
    VALUES (
        COALESCE(NEW.processed_by, 1),
        'updated_inbox_file',
        'processed_inbox_files',
        NEW.id,
        'Updated inbox file status: ' || NEW.filename || ' -> ' || NEW.status
    );
END;

-- Record migration
INSERT INTO schema_versions (version, name) VALUES (6, '006_processed_inbox_files');
