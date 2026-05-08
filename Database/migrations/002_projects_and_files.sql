-- Migration 002: Projects and Files
-- Created: 2026-03-27
-- Author: Lena (Database Architect)
-- Description: Adds project tracking and file registry tables, plus linking
--              columns to connect tasks, knowledge entries, and deliverables
--              to projects.
--
-- Design decisions:
--   - projects table uses a status state machine similar to tasks
--   - files table is a registry of all files in the system (inboxes, folders, etc.)
--   - file_links is a polymorphic join table that connects files to any entity
--     (projects, tasks, knowledge entries, team members) via entity_type + entity_id.
--     I chose this over four separate join tables because the relationship is
--     uniform ("file X is associated with entity Y") and querying "all files for
--     entity Z" is the dominant access pattern.
--   - Tasks, knowledge_entries, and deliverables get a nullable project_id FK
--     to link them to projects. This is a direct FK rather than polymorphic
--     because the relationship is 1:many and well-defined.

-- Record the migration
INSERT INTO schema_versions (version, name) VALUES (2, '002_projects_and_files');

-- ============================================================================
-- 1. PROJECTS
-- ============================================================================
-- Tracks different projects {{OWNER}} is working on. Acts as an umbrella that
-- groups tasks, deliverables, knowledge entries, and files.

CREATE TABLE projects (
    id              INTEGER PRIMARY KEY,
    name            TEXT    NOT NULL UNIQUE,
    description     TEXT,
    status          TEXT    NOT NULL DEFAULT 'active'
                        CHECK (status IN ('planning', 'active', 'on_hold', 'completed', 'archived')),
    start_date      TEXT,                 -- ISO 8601 date
    end_date        TEXT,                 -- ISO 8601 date (nullable = open-ended)
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_projects_status ON projects (status);

-- Auto-update updated_at on projects
CREATE TRIGGER trg_projects_updated_at
AFTER UPDATE ON projects
FOR EACH ROW
BEGIN
    UPDATE projects SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;


-- ============================================================================
-- 2. LINK EXISTING TABLES TO PROJECTS
-- ============================================================================
-- SQLite supports ALTER TABLE ... ADD COLUMN but not ADD CONSTRAINT.
-- New FK columns are nullable (existing rows have no project), and FK
-- enforcement happens at the PRAGMA level which is already enabled.

-- Tasks can belong to a project
ALTER TABLE tasks ADD COLUMN project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL;

-- Knowledge entries can belong to a project
ALTER TABLE knowledge_entries ADD COLUMN project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL;

-- Deliverables can belong to a project
ALTER TABLE deliverables ADD COLUMN project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL;

-- Indexes for the new FK columns -- "show me all tasks/entries/deliverables for project X"
CREATE INDEX idx_tasks_project_id ON tasks (project_id);
CREATE INDEX idx_knowledge_entries_project_id ON knowledge_entries (project_id);
CREATE INDEX idx_deliverables_project_id ON deliverables (project_id);


-- ============================================================================
-- 3. FILES
-- ============================================================================
-- A registry of all files in the system. This gives visibility into what
-- lives in Team Inbox, Owners Inbox, and other folders.
-- file_type is the format/extension (e.g., 'md', 'pdf', 'png'), not a
-- semantic category -- that role is served by the linking relationships.

CREATE TABLE files (
    id              INTEGER PRIMARY KEY,
    name            TEXT    NOT NULL,       -- filename (e.g., 'research-brief.md')
    path            TEXT    NOT NULL UNIQUE, -- full relative path from project root
    file_type       TEXT,                   -- format/extension (e.g., 'md', 'pdf', 'png')
    description     TEXT,                   -- what this file is about
    added_by        INTEGER REFERENCES team_members(id) ON DELETE RESTRICT,
    added_at        TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_files_file_type ON files (file_type);
CREATE INDEX idx_files_added_by ON files (added_by);

-- Auto-update updated_at on files
CREATE TRIGGER trg_files_updated_at
AFTER UPDATE ON files
FOR EACH ROW
BEGIN
    UPDATE files SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;


-- ============================================================================
-- 4. FILE LINKS (polymorphic join)
-- ============================================================================
-- Connects files to any entity: projects, tasks, knowledge entries, or
-- team members. entity_type + entity_id is the polymorphic FK pattern
-- (same approach as activity_history).
--
-- I chose not to FK-constrain entity_id for the same reason as
-- activity_history: it would require one join table per entity type,
-- adding schema complexity without meaningful integrity gain (the
-- entity_type CHECK constraint + application logic handles this).

CREATE TABLE file_links (
    id              INTEGER PRIMARY KEY,
    file_id         INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    entity_type     TEXT    NOT NULL
                        CHECK (entity_type IN ('project', 'task', 'knowledge_entry', 'team_member', 'deliverable')),
    entity_id       INTEGER NOT NULL,
    notes           TEXT,                   -- why this file is linked to this entity
    linked_at       TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE (file_id, entity_type, entity_id)  -- prevent duplicate links
);

CREATE INDEX idx_file_links_file_id ON file_links (file_id);
CREATE INDEX idx_file_links_entity ON file_links (entity_type, entity_id);


-- ============================================================================
-- 5. UPDATED VIEWS
-- ============================================================================

-- Recreate v_open_tasks to include project info
DROP VIEW IF EXISTS v_open_tasks;
CREATE VIEW v_open_tasks AS
SELECT
    t.id,
    t.title,
    t.status,
    t.priority,
    t.deadline,
    t.created_at,
    assignee.name AS assigned_to_name,
    assigner.name AS assigned_by_name,
    p.name AS project_name
FROM tasks t
LEFT JOIN team_members assignee ON t.assigned_to = assignee.id
LEFT JOIN team_members assigner ON t.assigned_by = assigner.id
LEFT JOIN projects p ON t.project_id = p.id
WHERE t.status IN ('pending', 'in_progress', 'blocked')
ORDER BY
    CASE t.priority
        WHEN 'urgent' THEN 1
        WHEN 'high'   THEN 2
        WHEN 'normal' THEN 3
        WHEN 'low'    THEN 4
    END,
    t.created_at;

-- Project overview: active projects with counts of linked entities
CREATE VIEW v_project_summary AS
SELECT
    p.id,
    p.name,
    p.status,
    p.start_date,
    p.end_date,
    (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.status NOT IN ('completed', 'cancelled')) AS open_tasks,
    (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.status = 'completed') AS completed_tasks,
    (SELECT COUNT(*) FROM deliverables d WHERE d.project_id = p.id) AS deliverable_count,
    (SELECT COUNT(*) FROM knowledge_entries ke WHERE ke.project_id = p.id AND ke.is_archived = 0) AS knowledge_count,
    (SELECT COUNT(*) FROM file_links fl WHERE fl.entity_type = 'project' AND fl.entity_id = p.id) AS file_count,
    p.created_at,
    p.updated_at
FROM projects p
ORDER BY
    CASE p.status
        WHEN 'active'    THEN 1
        WHEN 'planning'  THEN 2
        WHEN 'on_hold'   THEN 3
        WHEN 'completed' THEN 4
        WHEN 'archived'  THEN 5
    END,
    p.start_date;

-- File registry: all files with their link counts
CREATE VIEW v_files AS
SELECT
    f.id,
    f.name,
    f.path,
    f.file_type,
    f.description,
    m.name AS added_by_name,
    f.added_at,
    (SELECT COUNT(*) FROM file_links fl WHERE fl.file_id = f.id) AS link_count
FROM files f
LEFT JOIN team_members m ON f.added_by = m.id
ORDER BY f.added_at DESC;
