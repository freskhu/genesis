-- Migration 008: FTS5 Full-Text Search + Procedural Memory
-- Date: 2026-04-07
-- Description: Adds FTS5 search index on knowledge_entries and procedural memory table

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA synchronous = NORMAL;

-- =============================================================================
-- 1. FTS5 Virtual Table for knowledge_entries
-- =============================================================================

CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5(
    title,
    content,
    summary,
    content=knowledge_entries,
    content_rowid=id
);

-- Trigger: sync on INSERT
CREATE TRIGGER IF NOT EXISTS knowledge_fts_ai AFTER INSERT ON knowledge_entries BEGIN
    INSERT INTO knowledge_fts(rowid, title, content, summary)
    VALUES (new.id, new.title, new.content, new.summary);
END;

-- Trigger: sync on DELETE
CREATE TRIGGER IF NOT EXISTS knowledge_fts_ad AFTER DELETE ON knowledge_entries BEGIN
    INSERT INTO knowledge_fts(knowledge_fts, rowid, title, content, summary)
    VALUES('delete', old.id, old.title, old.content, old.summary);
END;

-- Trigger: sync on UPDATE
CREATE TRIGGER IF NOT EXISTS knowledge_fts_au AFTER UPDATE ON knowledge_entries BEGIN
    INSERT INTO knowledge_fts(knowledge_fts, rowid, title, content, summary)
    VALUES('delete', old.id, old.title, old.content, old.summary);
    INSERT INTO knowledge_fts(rowid, title, content, summary)
    VALUES (new.id, new.title, new.content, new.summary);
END;

-- Populate FTS5 with existing data
INSERT INTO knowledge_fts(rowid, title, content, summary)
SELECT id, title, content, summary FROM knowledge_entries WHERE is_archived = 0;

-- =============================================================================
-- 2. Procedural Memory Table
-- =============================================================================

CREATE TABLE IF NOT EXISTS procedural_memory (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    trigger_pattern TEXT    NOT NULL,
    action          TEXT    NOT NULL,
    success_count   INTEGER DEFAULT 0,
    failure_count   INTEGER DEFAULT 0,
    success_rate    REAL    GENERATED ALWAYS AS (
        CASE WHEN success_count + failure_count = 0 THEN 0.0
        ELSE CAST(success_count AS REAL) / (success_count + failure_count) END
    ) STORED,
    source_agent    TEXT,
    last_used_at    TEXT,
    created_at      TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_procedural_memory_rate ON procedural_memory(success_rate DESC);

-- =============================================================================
-- 3. Search Helper View
-- =============================================================================

CREATE VIEW IF NOT EXISTS v_knowledge_search AS
SELECT ke.id, ke.title, ke.category, ke.summary,
       f.rank as relevance_score
FROM knowledge_fts f
JOIN knowledge_entries ke ON f.rowid = ke.id
WHERE ke.is_archived = 0
ORDER BY f.rank;

-- =============================================================================
-- 4. Migration Log
-- =============================================================================

INSERT INTO schema_versions (version, description)
VALUES (8, 'Add FTS5 search, procedural memory table');
