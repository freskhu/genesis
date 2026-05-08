-- Migration 001: Initial Schema
-- Created: 2026-03-27
-- Author: Lena (Database Architect)
-- Description: Creates all foundational tables for the AI Team database.
--
-- Domains covered:
--   1. Team Operations (roster, tasks, deliverables, activity history, hiring pipeline)
--   2. Knowledge Base (entries, tags, sources)
--   3. Daily Persistent Memory (memories, notes)
--
-- Design decisions documented inline.

-- ============================================================================
-- SCHEMA VERSION TRACKING
-- ============================================================================
-- Tracks which migrations have been applied. The database itself is the
-- source of truth for its own version history.

CREATE TABLE IF NOT EXISTS schema_versions (
    version     INTEGER PRIMARY KEY,
    name        TEXT    NOT NULL,
    applied_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

INSERT INTO schema_versions (version, name) VALUES (1, '001_initial_schema');

-- ============================================================================
-- 1. TEAM OPERATIONS
-- ============================================================================

-- 1a. TEAM MEMBERS
-- The canonical roster. Every person who has ever been on the team lives here.
-- Soft-delete via is_active rather than row deletion, because activity_history
-- and other tables reference members and we never want dangling references.

CREATE TABLE team_members (
    id              INTEGER PRIMARY KEY,  -- rowid alias for performance
    name            TEXT    NOT NULL UNIQUE,
    role            TEXT    NOT NULL,
    agent_path      TEXT,                 -- path to agent definition file (nullable for owner)
    profile_path    TEXT,                 -- path to Team/ profile markdown
    joined_at       TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Index on active members -- the most common filter.
CREATE INDEX idx_team_members_is_active ON team_members (is_active);


-- 1b. TASKS & ASSIGNMENTS
-- Models work items. A task is assigned by one member to another.
-- Status uses a CHECK constraint to enforce a valid state machine:
--   pending -> in_progress -> completed
--   pending -> cancelled
--   in_progress -> blocked -> in_progress
--   in_progress -> cancelled
--
-- I chose TEXT for status over a lookup table because the set of valid states
-- is small, stable, and best enforced at the constraint level.

CREATE TABLE tasks (
    id              INTEGER PRIMARY KEY,
    title           TEXT    NOT NULL,
    description     TEXT,
    status          TEXT    NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'in_progress', 'blocked', 'completed', 'cancelled')),
    priority        TEXT    NOT NULL DEFAULT 'normal'
                        CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    assigned_to     INTEGER REFERENCES team_members(id) ON DELETE RESTRICT,
    assigned_by     INTEGER REFERENCES team_members(id) ON DELETE RESTRICT,
    deadline        TEXT,                 -- ISO 8601 date or datetime, nullable
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    completed_at    TEXT                  -- set when status becomes 'completed'
);

-- Queries will filter by status and assignee constantly.
CREATE INDEX idx_tasks_status ON tasks (status);
CREATE INDEX idx_tasks_assigned_to ON tasks (assigned_to);
CREATE INDEX idx_tasks_assigned_by ON tasks (assigned_by);
-- Composite index for "show me active tasks for member X"
CREATE INDEX idx_tasks_assignee_status ON tasks (assigned_to, status);


-- 1c. DELIVERABLES LOG
-- Tracks what was produced, by whom, and where it lives.
-- Every deliverable links to the task that produced it (nullable for ad-hoc work).

CREATE TABLE deliverables (
    id              INTEGER PRIMARY KEY,
    title           TEXT    NOT NULL,
    description     TEXT,
    file_path       TEXT,                 -- path in Owners Inbox or elsewhere
    produced_by     INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT,
    task_id         INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
    delivered_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_deliverables_produced_by ON deliverables (produced_by);
CREATE INDEX idx_deliverables_task_id ON deliverables (task_id);
CREATE INDEX idx_deliverables_delivered_at ON deliverables (delivered_at);


-- 1d. ACTIVITY HISTORY
-- Polymorphic audit trail. Every meaningful action by any team member is logged.
-- entity_type + entity_id point to the affected row in any table.
-- I chose a single polymorphic table over per-entity history tables because:
--   - It gives a unified timeline view across the whole team
--   - The query "what happened today?" is a single table scan
--   - SQLite doesn't support table inheritance, so this is the pragmatic choice
-- Trade-off: no FK enforcement on entity_id (we accept this for audit flexibility).

CREATE TABLE activity_history (
    id              INTEGER PRIMARY KEY,
    actor_id        INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT,
    action          TEXT    NOT NULL,     -- e.g., 'created_task', 'completed_task', 'delivered', 'hired'
    entity_type     TEXT,                 -- e.g., 'task', 'deliverable', 'team_member', 'hiring_candidate'
    entity_id       INTEGER,             -- the PK of the affected row
    summary         TEXT    NOT NULL,     -- human-readable description of what happened
    metadata        TEXT,                 -- JSON blob for action-specific details
    occurred_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Timeline queries: "what happened today?", "what did member X do?"
CREATE INDEX idx_activity_history_occurred_at ON activity_history (occurred_at);
CREATE INDEX idx_activity_history_actor_id ON activity_history (actor_id);
CREATE INDEX idx_activity_history_entity ON activity_history (entity_type, entity_id);


-- 1e. HIRING PIPELINE
-- Tracks the journey from "we need someone" to "they're on the team."
-- Stages enforce the hiring workflow as a state machine.

CREATE TABLE hiring_candidates (
    id                  INTEGER PRIMARY KEY,
    role_title          TEXT    NOT NULL,     -- the role being hired for
    stage               TEXT    NOT NULL DEFAULT 'research'
                            CHECK (stage IN ('research', 'brief_complete', 'design', 'onboarding', 'hired', 'rejected')),
    research_brief_path TEXT,                 -- path to Maria's research brief
    agent_path          TEXT,                 -- path to the new agent definition (once created)
    profile_path        TEXT,                 -- path to Team/ profile (once created)
    requested_by        INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT,
    researched_by       INTEGER REFERENCES team_members(id) ON DELETE RESTRICT,
    designed_by         INTEGER REFERENCES team_members(id) ON DELETE RESTRICT,
    hired_member_id     INTEGER REFERENCES team_members(id) ON DELETE SET NULL,  -- links to team_members once hired
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at          TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_hiring_candidates_stage ON hiring_candidates (stage);


-- ============================================================================
-- 2. KNOWLEDGE BASE
-- ============================================================================

-- 2a. KNOWLEDGE ENTRIES
-- The team's indexed knowledge store. Entries are markdown-friendly text blobs
-- with structured metadata for search and organization.

CREATE TABLE knowledge_entries (
    id              INTEGER PRIMARY KEY,
    title           TEXT    NOT NULL,
    content         TEXT    NOT NULL,     -- the actual knowledge (markdown)
    category        TEXT,                 -- broad category for grouping
    added_by        INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT,
    is_archived     INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_knowledge_entries_category ON knowledge_entries (category);
CREATE INDEX idx_knowledge_entries_is_archived ON knowledge_entries (is_archived);


-- 2b. TAGS
-- A flat tag table with a many-to-many join to knowledge entries.
-- I chose a separate tags table over a comma-separated column because:
--   - It allows efficient tag-based filtering via joins
--   - It prevents typo-variant duplicates (tag names are UNIQUE)
--   - It supports tag renaming without updating every entry

CREATE TABLE tags (
    id      INTEGER PRIMARY KEY,
    name    TEXT    NOT NULL UNIQUE
);

CREATE TABLE knowledge_entry_tags (
    knowledge_entry_id  INTEGER NOT NULL REFERENCES knowledge_entries(id) ON DELETE CASCADE,
    tag_id              INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (knowledge_entry_id, tag_id)
);

-- Find all entries for a given tag efficiently.
CREATE INDEX idx_knowledge_entry_tags_tag_id ON knowledge_entry_tags (tag_id);


-- 2c. KNOWLEDGE SOURCES
-- Tracks provenance: where did a piece of knowledge come from?
-- An entry can have multiple sources (e.g., a file + a conversation).

CREATE TABLE knowledge_sources (
    id                  INTEGER PRIMARY KEY,
    knowledge_entry_id  INTEGER NOT NULL REFERENCES knowledge_entries(id) ON DELETE CASCADE,
    source_type         TEXT    NOT NULL CHECK (source_type IN ('file', 'conversation', 'research', 'web', 'other')),
    reference           TEXT    NOT NULL,     -- file path, URL, conversation ID, or description
    notes               TEXT,
    added_at            TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_knowledge_sources_entry_id ON knowledge_sources (knowledge_entry_id);
CREATE INDEX idx_knowledge_sources_type ON knowledge_sources (source_type);


-- ============================================================================
-- 3. DAILY PERSISTENT MEMORY
-- ============================================================================

-- 3a. DAILY MEMORIES
-- Short-lived or day-scoped items to remember. These are things like
-- "the owner mentioned he's on vacation next week" or "deploy is frozen until Friday."
-- They have an optional expiry date so stale memories can be cleaned up.

CREATE TABLE daily_memories (
    id              INTEGER PRIMARY KEY,
    content         TEXT    NOT NULL,
    context         TEXT,                 -- what situation prompted this memory
    added_by        INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT,
    is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    expires_at      TEXT,                 -- ISO 8601; NULL means no expiry
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_daily_memories_is_active ON daily_memories (is_active);
CREATE INDEX idx_daily_memories_expires_at ON daily_memories (expires_at);


-- 3b. PERSISTENT NOTES
-- Long-lived context that carries across conversations and days.
-- These are more structured than memories: they have titles and categories,
-- and are meant to be actively curated rather than accumulating indefinitely.

CREATE TABLE persistent_notes (
    id              INTEGER PRIMARY KEY,
    title           TEXT    NOT NULL,
    content         TEXT    NOT NULL,
    category        TEXT,                 -- e.g., 'preferences', 'project_context', 'decisions'
    added_by        INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT,
    is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_persistent_notes_category ON persistent_notes (category);
CREATE INDEX idx_persistent_notes_is_active ON persistent_notes (is_active);


-- ============================================================================
-- CONVENIENCE VIEWS
-- ============================================================================

-- Active team roster (what "who's on the team?" queries hit)
CREATE VIEW v_active_roster AS
SELECT id, name, role, agent_path, profile_path, joined_at
FROM team_members
WHERE is_active = 1
ORDER BY joined_at;

-- Open tasks grouped by assignee
CREATE VIEW v_open_tasks AS
SELECT
    t.id,
    t.title,
    t.status,
    t.priority,
    t.deadline,
    t.created_at,
    assignee.name AS assigned_to_name,
    assigner.name AS assigned_by_name
FROM tasks t
LEFT JOIN team_members assignee ON t.assigned_to = assignee.id
LEFT JOIN team_members assigner ON t.assigned_by = assigner.id
WHERE t.status IN ('pending', 'in_progress', 'blocked')
ORDER BY
    CASE t.priority
        WHEN 'urgent' THEN 1
        WHEN 'high'   THEN 2
        WHEN 'normal' THEN 3
        WHEN 'low'    THEN 4
    END,
    t.created_at;

-- Recent activity feed (last 50 events)
CREATE VIEW v_recent_activity AS
SELECT
    ah.id,
    m.name AS actor_name,
    ah.action,
    ah.entity_type,
    ah.entity_id,
    ah.summary,
    ah.occurred_at
FROM activity_history ah
JOIN team_members m ON ah.actor_id = m.id
ORDER BY ah.occurred_at DESC
LIMIT 50;

-- Hiring pipeline status
CREATE VIEW v_hiring_pipeline AS
SELECT
    hc.id,
    hc.role_title,
    hc.stage,
    requester.name AS requested_by_name,
    researcher.name AS researched_by_name,
    designer.name AS designed_by_name,
    hired.name AS hired_member_name,
    hc.created_at
FROM hiring_candidates hc
JOIN team_members requester ON hc.requested_by = requester.id
LEFT JOIN team_members researcher ON hc.researched_by = researcher.id
LEFT JOIN team_members designer ON hc.designed_by = designer.id
LEFT JOIN team_members hired ON hc.hired_member_id = hired.id
ORDER BY
    CASE hc.stage
        WHEN 'research'       THEN 1
        WHEN 'brief_complete' THEN 2
        WHEN 'design'         THEN 3
        WHEN 'onboarding'     THEN 4
        WHEN 'hired'          THEN 5
        WHEN 'rejected'       THEN 6
    END,
    hc.created_at;

-- Active knowledge (non-archived entries with their tags)
CREATE VIEW v_knowledge AS
SELECT
    ke.id,
    ke.title,
    ke.content,
    ke.category,
    m.name AS added_by_name,
    ke.created_at,
    ke.updated_at,
    GROUP_CONCAT(t.name, ', ') AS tags
FROM knowledge_entries ke
JOIN team_members m ON ke.added_by = m.id
LEFT JOIN knowledge_entry_tags ket ON ke.id = ket.knowledge_entry_id
LEFT JOIN tags t ON ket.tag_id = t.id
WHERE ke.is_archived = 0
GROUP BY ke.id
ORDER BY ke.updated_at DESC;

-- Active daily memories (not expired, still active)
CREATE VIEW v_active_memories AS
SELECT
    dm.id,
    dm.content,
    dm.context,
    m.name AS added_by_name,
    dm.expires_at,
    dm.created_at
FROM daily_memories dm
JOIN team_members m ON dm.added_by = m.id
WHERE dm.is_active = 1
  AND (dm.expires_at IS NULL OR dm.expires_at > strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
ORDER BY dm.created_at DESC;

-- Active persistent notes
CREATE VIEW v_active_notes AS
SELECT
    pn.id,
    pn.title,
    pn.content,
    pn.category,
    m.name AS added_by_name,
    pn.created_at,
    pn.updated_at
FROM persistent_notes pn
JOIN team_members m ON pn.added_by = m.id
WHERE pn.is_active = 1
ORDER BY pn.updated_at DESC;


-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update updated_at timestamps on row modification.
-- SQLite doesn't have a generic "on any update" mechanism, so we need
-- one trigger per table that has an updated_at column.

CREATE TRIGGER trg_team_members_updated_at
AFTER UPDATE ON team_members
FOR EACH ROW
BEGIN
    UPDATE team_members SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;

CREATE TRIGGER trg_tasks_updated_at
AFTER UPDATE ON tasks
FOR EACH ROW
BEGIN
    UPDATE tasks SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;

CREATE TRIGGER trg_hiring_candidates_updated_at
AFTER UPDATE ON hiring_candidates
FOR EACH ROW
BEGIN
    UPDATE hiring_candidates SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;

CREATE TRIGGER trg_knowledge_entries_updated_at
AFTER UPDATE ON knowledge_entries
FOR EACH ROW
BEGIN
    UPDATE knowledge_entries SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;

CREATE TRIGGER trg_persistent_notes_updated_at
AFTER UPDATE ON persistent_notes
FOR EACH ROW
BEGIN
    UPDATE persistent_notes SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;

-- Auto-set completed_at when a task moves to 'completed'
CREATE TRIGGER trg_tasks_completed_at
AFTER UPDATE OF status ON tasks
FOR EACH ROW
WHEN NEW.status = 'completed' AND OLD.status != 'completed'
BEGIN
    UPDATE tasks SET completed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;
