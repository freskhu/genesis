-- Genesis schema (generic tables only)
-- Source: agentic-os internal db, sanitized for public template

CREATE TABLE schema_versions (
    version     INTEGER PRIMARY KEY,
    name        TEXT    NOT NULL,
    applied_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);


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

CREATE INDEX idx_team_members_is_active ON team_members (is_active);
CREATE TRIGGER trg_team_members_updated_at
AFTER UPDATE ON team_members
FOR EACH ROW
BEGIN
    UPDATE team_members SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;
CREATE TRIGGER trg_activity_team_members_insert
AFTER INSERT ON team_members
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (NEW.id, 'created_team_member', 'team_member', NEW.id,
            'New team member joined: ' || NEW.name || ' (' || NEW.role || ')',
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;
CREATE TRIGGER trg_activity_team_members_update
AFTER UPDATE ON team_members
FOR EACH ROW
WHEN OLD.updated_at != NEW.updated_at
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (NEW.id, 'updated_team_member', 'team_member', NEW.id,
            'Updated team member: ' || NEW.name ||
            CASE WHEN OLD.is_active != NEW.is_active AND NEW.is_active = 0
                 THEN ' (deactivated)'
                 WHEN OLD.is_active != NEW.is_active AND NEW.is_active = 1
                 THEN ' (reactivated)'
                 WHEN OLD.role != NEW.role
                 THEN ' (role: ' || OLD.role || ' -> ' || NEW.role || ')'
                 ELSE '' END,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

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
, project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL);

CREATE INDEX idx_tasks_status ON tasks (status);
CREATE INDEX idx_tasks_assigned_to ON tasks (assigned_to);
CREATE INDEX idx_tasks_assigned_by ON tasks (assigned_by);
CREATE INDEX idx_tasks_assignee_status ON tasks (assigned_to, status);
CREATE TRIGGER trg_tasks_updated_at
AFTER UPDATE ON tasks
FOR EACH ROW
BEGIN
    UPDATE tasks SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;
CREATE TRIGGER trg_tasks_completed_at
AFTER UPDATE OF status ON tasks
FOR EACH ROW
WHEN NEW.status = 'completed' AND OLD.status != 'completed'
BEGIN
    UPDATE tasks SET completed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;
CREATE INDEX idx_tasks_project_id ON tasks (project_id);
CREATE TRIGGER trg_activity_tasks_insert
AFTER INSERT ON tasks
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (COALESCE(NEW.assigned_by, 1), 'created_task', 'task', NEW.id,
            'Created task: ' || NEW.title ||
            CASE WHEN NEW.assigned_to IS NOT NULL
                 THEN ' (assigned to ' || (SELECT name FROM team_members WHERE id = NEW.assigned_to) || ')'
                 ELSE ' (unassigned)' END,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;
CREATE TRIGGER trg_activity_tasks_update
AFTER UPDATE ON tasks
FOR EACH ROW
WHEN OLD.updated_at != NEW.updated_at
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (COALESCE(NEW.assigned_by, 1), 'updated_task', 'task', NEW.id,
            'Updated task: ' || NEW.title ||
            CASE WHEN OLD.status != NEW.status
                 THEN ' (status: ' || OLD.status || ' -> ' || NEW.status || ')'
                 WHEN OLD.assigned_to IS DISTINCT FROM NEW.assigned_to AND NEW.assigned_to IS NOT NULL
                 THEN ' (reassigned to ' || (SELECT name FROM team_members WHERE id = NEW.assigned_to) || ')'
                 ELSE '' END,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

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

CREATE INDEX idx_activity_history_occurred_at ON activity_history (occurred_at);
CREATE INDEX idx_activity_history_actor_id ON activity_history (actor_id);
CREATE INDEX idx_activity_history_entity ON activity_history (entity_type, entity_id);
CREATE TRIGGER activity_fts_ai AFTER INSERT ON activity_history BEGIN
    INSERT INTO activity_fts(rowid, summary) VALUES (new.id, new.summary);
END;

CREATE TABLE deliverables (
    id              INTEGER PRIMARY KEY,
    title           TEXT    NOT NULL,
    description     TEXT,
    file_path       TEXT,                 -- path in Owners Inbox or elsewhere
    produced_by     INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT,
    task_id         INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
    delivered_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
, project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL);

CREATE INDEX idx_deliverables_produced_by ON deliverables (produced_by);
CREATE INDEX idx_deliverables_task_id ON deliverables (task_id);
CREATE INDEX idx_deliverables_delivered_at ON deliverables (delivered_at);
CREATE INDEX idx_deliverables_project_id ON deliverables (project_id);
CREATE TRIGGER trg_activity_deliverables_insert
AFTER INSERT ON deliverables
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (NEW.produced_by, 'created_deliverable', 'deliverable', NEW.id,
            'Delivered: ' || NEW.title ||
            ' by ' || (SELECT name FROM team_members WHERE id = NEW.produced_by),
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

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
CREATE TRIGGER trg_projects_updated_at
AFTER UPDATE ON projects
FOR EACH ROW
BEGIN
    UPDATE projects SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;

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
CREATE TRIGGER trg_files_updated_at
AFTER UPDATE ON files
FOR EACH ROW
BEGIN
    UPDATE files SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;

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

CREATE TABLE tags (
    id      INTEGER PRIMARY KEY,
    name    TEXT    NOT NULL UNIQUE
);


CREATE TABLE knowledge_entries (
    id              INTEGER PRIMARY KEY,
    title           TEXT    NOT NULL,
    content         TEXT    NOT NULL,     -- the actual knowledge (markdown)
    category        TEXT,                 -- broad category for grouping
    added_by        INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT,
    is_archived     INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
, project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL, summary TEXT, valid_from TEXT, valid_to TEXT, memory_type TEXT DEFAULT 'fact' CHECK(memory_type IN ('fact', 'decision', 'preference', 'event', 'discovery', 'advice')));

CREATE INDEX idx_knowledge_entries_category ON knowledge_entries (category);
CREATE INDEX idx_knowledge_entries_is_archived ON knowledge_entries (is_archived);
CREATE TRIGGER trg_knowledge_entries_updated_at
AFTER UPDATE ON knowledge_entries
FOR EACH ROW
BEGIN
    UPDATE knowledge_entries SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE id = NEW.id;
END;
CREATE INDEX idx_knowledge_entries_project_id ON knowledge_entries (project_id);
CREATE TRIGGER trg_activity_knowledge_entries_insert
AFTER INSERT ON knowledge_entries
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (NEW.added_by, 'created_knowledge_entry', 'knowledge_entry', NEW.id,
            'Added knowledge entry: ' || NEW.title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;
CREATE TRIGGER trg_activity_knowledge_entries_update
AFTER UPDATE ON knowledge_entries
FOR EACH ROW
WHEN OLD.updated_at != NEW.updated_at
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (NEW.added_by, 'updated_knowledge_entry', 'knowledge_entry', NEW.id,
            'Updated knowledge entry: ' || NEW.title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;
CREATE TRIGGER knowledge_fts_ai AFTER INSERT ON knowledge_entries
WHEN new.is_archived = 0
BEGIN
    INSERT INTO knowledge_fts(rowid, title, content, summary)
    VALUES (new.id, new.title, new.content, new.summary);
END;
CREATE TRIGGER knowledge_fts_ad AFTER DELETE ON knowledge_entries BEGIN
    INSERT INTO knowledge_fts(knowledge_fts, rowid, title, content, summary)
    VALUES('delete', old.id, old.title, old.content, old.summary);
END;
CREATE TRIGGER knowledge_fts_au AFTER UPDATE ON knowledge_entries BEGIN
    -- Always remove old entry from index (if it was there)
    INSERT INTO knowledge_fts(knowledge_fts, rowid, title, content, summary)
    VALUES('delete', old.id, old.title, old.content, old.summary);
    -- Only re-insert if the new state is active
    INSERT INTO knowledge_fts(rowid, title, content, summary)
    SELECT new.id, new.title, new.content, new.summary
    WHERE new.is_archived = 0;
END;

CREATE TABLE knowledge_entry_tags (
    knowledge_entry_id  INTEGER NOT NULL REFERENCES knowledge_entries(id) ON DELETE CASCADE,
    tag_id              INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (knowledge_entry_id, tag_id)
);

CREATE INDEX idx_knowledge_entry_tags_tag_id ON knowledge_entry_tags (tag_id);

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

CREATE INDEX idx_processed_inbox_files_status ON processed_inbox_files (status);
CREATE TRIGGER trg_processed_inbox_files_updated_at
    AFTER UPDATE ON processed_inbox_files
    FOR EACH ROW
BEGIN
    UPDATE processed_inbox_files SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = NEW.id;
END;
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

CREATE TABLE llm_calls (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT,
    agent_name TEXT,
    model TEXT NOT NULL,
    input_tokens INTEGER,
    output_tokens INTEGER,
    cache_read_tokens INTEGER,
    cache_write_tokens INTEGER,
    latency_ms INTEGER,
    cost_usd REAL,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_llm_calls_agent_created
    ON llm_calls (agent_name, created_at);
CREATE INDEX idx_llm_calls_task_id
    ON llm_calls (task_id);

CREATE TABLE procedural_memory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trigger_pattern TEXT NOT NULL,
    action TEXT NOT NULL,
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    success_rate REAL GENERATED ALWAYS AS (
        CASE WHEN success_count + failure_count = 0 THEN 0.0
        ELSE CAST(success_count AS REAL) / (success_count + failure_count)
        END
    ) STORED,
    source_agent TEXT,
    last_used_at TEXT,
    created_at TEXT DEFAULT (datetime('now'))
, name TEXT, steps TEXT, context_requirements TEXT, tags TEXT);

CREATE INDEX idx_procedural_memory_rate
    ON procedural_memory(success_rate DESC);

CREATE TABLE agent_diary (
    id INTEGER PRIMARY KEY,
    agent_id INTEGER NOT NULL REFERENCES team_members(id),
    entry TEXT NOT NULL,
    topic TEXT DEFAULT 'general',
    session_id TEXT,
    importance INTEGER DEFAULT 5 CHECK(importance >= 1 AND importance <= 10),
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX idx_diary_agent ON agent_diary(agent_id);
CREATE INDEX idx_diary_topic ON agent_diary(topic);
CREATE INDEX idx_diary_importance ON agent_diary(importance DESC);

CREATE TABLE diary_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            agent_name TEXT NOT NULL,
            topic TEXT DEFAULT 'general',
            content TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now'))
        );

CREATE INDEX idx_diary_agent_ts ON diary_entries(agent_name, created_at DESC);

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

CREATE TABLE drawers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drawer_id TEXT UNIQUE NOT NULL,
            content TEXT NOT NULL,
            wing TEXT NOT NULL,
            room TEXT NOT NULL,
            hall TEXT DEFAULT 'hall_discoveries',
            tier TEXT DEFAULT 'warm',
            source_file TEXT DEFAULT '',
            chunk_index INTEGER DEFAULT 0,
            added_by TEXT DEFAULT 'migrated',
            filed_at TEXT DEFAULT (datetime('now')),
            metadata TEXT DEFAULT '{}'
        );

CREATE INDEX idx_drawers_wing ON drawers(wing);
CREATE INDEX idx_drawers_room ON drawers(room);
CREATE INDEX idx_drawers_hall ON drawers(hall);
CREATE INDEX idx_drawers_tier ON drawers(tier);
CREATE INDEX idx_drawers_wing_room ON drawers(wing, room);
CREATE INDEX idx_drawers_source ON drawers(source_file);
CREATE INDEX idx_drawers_drawer_id ON drawers(drawer_id);
CREATE TRIGGER drawers_fts_ai AFTER INSERT ON drawers BEGIN
            INSERT INTO drawers_fts(rowid, content, wing, room, hall, source_file)
            VALUES (new.id, new.content, new.wing, new.room, new.hall, new.source_file);
        END;
CREATE TRIGGER drawers_fts_ad AFTER DELETE ON drawers BEGIN
            DELETE FROM drawers_fts WHERE rowid = old.id;
        END;
CREATE TRIGGER drawers_fts_au AFTER UPDATE ON drawers BEGIN
            DELETE FROM drawers_fts WHERE rowid = old.id;
            INSERT INTO drawers_fts(rowid, content, wing, room, hall, source_file)
            VALUES (new.id, new.content, new.wing, new.room, new.hall, new.source_file);
        END;

CREATE TABLE kg_entities (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT DEFAULT 'unknown',
            properties TEXT DEFAULT '{}',
            created_at TEXT DEFAULT (datetime('now'))
        );


CREATE TABLE kg_triples (
            id TEXT PRIMARY KEY,
            subject TEXT NOT NULL,
            predicate TEXT NOT NULL,
            object TEXT NOT NULL,
            valid_from TEXT,
            valid_to TEXT,
            confidence REAL DEFAULT 1.0,
            source TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
        );

CREATE INDEX idx_kg_triples_subject ON kg_triples(subject);
CREATE INDEX idx_kg_triples_object ON kg_triples(object);
CREATE INDEX idx_kg_triples_predicate ON kg_triples(predicate);

CREATE VIRTUAL TABLE knowledge_fts USING fts5(
    title,
    content,
    summary,
    content=knowledge_entries,
    content_rowid=id
);


CREATE VIRTUAL TABLE activity_fts USING fts5(
    summary,
    content='activity_history',
    content_rowid='id',
    tokenize='porter unicode61'
);


CREATE VIRTUAL TABLE drawers_fts USING fts5(
            content, wing, room, hall, source_file,
            content='drawers', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );


