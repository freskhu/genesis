-- Migration 010: Memory System Improvements
-- Date: 2026-04-09
-- Based on: Maria's research (state-of-the-art 2026) + MemPalace analysis
-- Changes:
--   1. Temporal validity on knowledge_entries (valid_from, valid_to)
--   2. Memory type classification (memory_type column)
--   3. Knowledge relations table (cross-referencing / tunnels)
--   4. Agent diary table (persistent per-agent learning)
--   5. Procedural memory upgrade (name, steps, context, tags)
--   6. FTS5 on activity_history (full-text search on logs)
--   7. New views: v_knowledge_relations, v_agent_diary, v_temporal_knowledge
--   8. Updated view: v_knowledge_catalog (includes memory_type, valid_from, valid_to)

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA synchronous = NORMAL;

-- ============================================================
-- 1. Temporal Validity
-- ============================================================
ALTER TABLE knowledge_entries ADD COLUMN valid_from TEXT;
ALTER TABLE knowledge_entries ADD COLUMN valid_to TEXT;

-- ============================================================
-- 2. Memory Type Classification (orthogonal to category)
-- ============================================================
ALTER TABLE knowledge_entries ADD COLUMN memory_type TEXT DEFAULT 'fact'
  CHECK(memory_type IN ('fact', 'decision', 'preference', 'event', 'discovery', 'advice'));

-- ============================================================
-- 3. Knowledge Relations (cross-referencing between entries)
-- ============================================================
CREATE TABLE IF NOT EXISTS knowledge_relations (
    id INTEGER PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES knowledge_entries(id),
    target_id INTEGER NOT NULL REFERENCES knowledge_entries(id),
    relation_type TEXT NOT NULL CHECK(relation_type IN (
        'related_to', 'supersedes', 'contradicts', 'depends_on', 'extends'
    )),
    confidence REAL DEFAULT 1.0 CHECK(confidence >= 0.0 AND confidence <= 1.0),
    created_by INTEGER REFERENCES team_members(id),
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE(source_id, target_id, relation_type)
);
CREATE INDEX IF NOT EXISTS idx_knowledge_relations_source ON knowledge_relations(source_id);
CREATE INDEX IF NOT EXISTS idx_knowledge_relations_target ON knowledge_relations(target_id);
CREATE INDEX IF NOT EXISTS idx_knowledge_relations_type ON knowledge_relations(relation_type);

-- ============================================================
-- 4. Agent Diary (persistent per-agent observation logs)
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_diary (
    id INTEGER PRIMARY KEY,
    agent_id INTEGER NOT NULL REFERENCES team_members(id),
    entry TEXT NOT NULL,
    topic TEXT DEFAULT 'general',
    session_id TEXT,
    importance INTEGER DEFAULT 5 CHECK(importance >= 1 AND importance <= 10),
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_diary_agent ON agent_diary(agent_id);
CREATE INDEX IF NOT EXISTS idx_diary_topic ON agent_diary(topic);
CREATE INDEX IF NOT EXISTS idx_diary_importance ON agent_diary(importance DESC);

-- ============================================================
-- 5. Procedural Memory Upgrade
-- ============================================================
ALTER TABLE procedural_memory ADD COLUMN name TEXT;
ALTER TABLE procedural_memory ADD COLUMN steps TEXT;  -- JSON array
ALTER TABLE procedural_memory ADD COLUMN context_requirements TEXT;
ALTER TABLE procedural_memory ADD COLUMN tags TEXT;  -- comma-separated

-- ============================================================
-- 6. FTS5 on activity_history
-- ============================================================
CREATE VIRTUAL TABLE IF NOT EXISTS activity_fts USING fts5(
    summary,
    content='activity_history',
    content_rowid='id',
    tokenize='porter unicode61'
);

-- Backfill existing data
INSERT INTO activity_fts(rowid, summary) SELECT id, summary FROM activity_history;

-- Keep in sync
CREATE TRIGGER IF NOT EXISTS activity_fts_ai AFTER INSERT ON activity_history BEGIN
    INSERT INTO activity_fts(rowid, summary) VALUES (new.id, new.summary);
END;

-- ============================================================
-- 7. New Views
-- ============================================================
CREATE VIEW IF NOT EXISTS v_knowledge_relations AS
SELECT kr.id, kr.relation_type, kr.confidence,
    s.id AS source_id, s.title AS source_title, s.category AS source_category,
    t.id AS target_id, t.title AS target_title, t.category AS target_category,
    kr.created_at
FROM knowledge_relations kr
JOIN knowledge_entries s ON kr.source_id = s.id
JOIN knowledge_entries t ON kr.target_id = t.id
WHERE s.is_archived = 0 AND t.is_archived = 0
ORDER BY kr.created_at DESC;

CREATE VIEW IF NOT EXISTS v_agent_diary AS
SELECT ad.id, tm.name AS agent_name, ad.entry, ad.topic, ad.importance, ad.session_id, ad.created_at
FROM agent_diary ad
JOIN team_members tm ON ad.agent_id = tm.id
ORDER BY ad.created_at DESC;

CREATE VIEW IF NOT EXISTS v_temporal_knowledge AS
SELECT ke.id, ke.title, ke.category, ke.memory_type, ke.valid_from, ke.valid_to,
    CASE WHEN ke.valid_to IS NULL THEN 'current' ELSE 'superseded' END AS temporal_status,
    ke.summary, ke.updated_at
FROM knowledge_entries ke
WHERE ke.is_archived = 0
ORDER BY ke.valid_from DESC NULLS LAST;

-- ============================================================
-- 8. Updated v_knowledge_catalog (requires DROP + CREATE)
-- ============================================================
DROP VIEW IF EXISTS v_knowledge_catalog;
CREATE VIEW v_knowledge_catalog AS
SELECT ke.id, ke.title, ke.category, ke.memory_type,
  GROUP_CONCAT(t.name, ', ') AS tags,
  COALESCE(ke.summary, SUBSTR(ke.content, 1, 150)) AS preview,
  ke.valid_from, ke.valid_to, ke.updated_at
FROM knowledge_entries ke
LEFT JOIN knowledge_entry_tags ket ON ke.id = ket.knowledge_entry_id
LEFT JOIN tags t ON ket.tag_id = t.id
WHERE ke.is_archived = 0
GROUP BY ke.id
ORDER BY ke.category, ke.updated_at DESC;
