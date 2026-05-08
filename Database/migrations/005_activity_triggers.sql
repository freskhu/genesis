-- Migration 005: Activity History Triggers
-- Creates AFTER INSERT and AFTER UPDATE triggers on all key tables
-- to automatically log events into activity_history.
--
-- Actor resolution:
--   - Tables with added_by/assigned_by/produced_by/requested_by -> use that column
--   - Strategy tables without a user FK -> default to actor_id = 1 (the orchestrator/system)
--
-- Date: 2026-03-30
-- Author: Lena (Database Architect)

-- ============================================================
-- 1. frameworks
-- ============================================================

CREATE TRIGGER trg_activity_frameworks_insert
AFTER INSERT ON frameworks
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_framework', 'framework', NEW.id,
            'Added framework: ' || NEW.name,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

CREATE TRIGGER trg_activity_frameworks_update
AFTER UPDATE ON frameworks
FOR EACH ROW
WHEN OLD.updated_at != NEW.updated_at  -- avoid firing on the updated_at trigger's own UPDATE
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'updated_framework', 'framework', NEW.id,
            'Updated framework: ' || NEW.name,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 2. professor_terminology (INSERT only)
-- ============================================================

CREATE TRIGGER trg_activity_professor_terminology_insert
AFTER INSERT ON professor_terminology
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_terminology', 'professor_terminology', NEW.id,
            'Added terminology: ' || NEW.correct_term || ' (replaces: ' || NEW.wrong_term || ')',
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 3. strategy_companies (INSERT + UPDATE)
-- ============================================================

CREATE TRIGGER trg_activity_strategy_companies_insert
AFTER INSERT ON strategy_companies
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_company', 'strategy_company', NEW.id,
            'Added strategy company: ' || NEW.name || ' (' || NEW.sector || ')',
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

CREATE TRIGGER trg_activity_strategy_companies_update
AFTER UPDATE ON strategy_companies
FOR EACH ROW
WHEN OLD.updated_at != NEW.updated_at
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'updated_company', 'strategy_company', NEW.id,
            'Updated strategy company: ' || NEW.name,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 4. company_frameworks (INSERT only)
-- ============================================================

CREATE TRIGGER trg_activity_company_frameworks_insert
AFTER INSERT ON company_frameworks
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_company_framework', 'company_framework', NEW.id,
            'Linked framework to company: ' ||
            (SELECT name FROM frameworks WHERE id = NEW.framework_id) ||
            ' -> ' ||
            (SELECT name FROM strategy_companies WHERE id = NEW.company_id) ||
            ' (' || NEW.relevance || ')',
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 5. solved_cases (INSERT + UPDATE)
-- ============================================================

CREATE TRIGGER trg_activity_solved_cases_insert
AFTER INSERT ON solved_cases
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_solved_case', 'solved_case', NEW.id,
            'Added solved case: ' ||
            (SELECT name FROM strategy_companies WHERE id = NEW.company_id) ||
            ' Q' || NEW.question_number || ' - ' || NEW.question_title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

CREATE TRIGGER trg_activity_solved_cases_update
AFTER UPDATE ON solved_cases
FOR EACH ROW
WHEN OLD.updated_at != NEW.updated_at
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'updated_solved_case', 'solved_case', NEW.id,
            'Updated solved case: ' ||
            (SELECT name FROM strategy_companies WHERE id = NEW.company_id) ||
            ' Q' || NEW.question_number || ' - ' || NEW.question_title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 6. knowledge_entries (INSERT + UPDATE)
-- ============================================================

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

-- ============================================================
-- 7. question_types (INSERT + UPDATE)
-- ============================================================

CREATE TRIGGER trg_activity_question_types_insert
AFTER INSERT ON question_types
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_question_type', 'question_type', NEW.id,
            'Added question type ' || NEW.type_code || ': ' || NEW.title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

CREATE TRIGGER trg_activity_question_types_update
AFTER UPDATE ON question_types
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'updated_question_type', 'question_type', NEW.id,
            'Updated question type ' || NEW.type_code || ': ' || NEW.title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 8. question_type_frameworks (INSERT only)
-- ============================================================

CREATE TRIGGER trg_activity_question_type_frameworks_insert
AFTER INSERT ON question_type_frameworks
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_question_type_framework', 'question_type_framework', NEW.id,
            'Linked framework to question type: ' ||
            (SELECT name FROM frameworks WHERE id = NEW.framework_id) ||
            ' -> Type ' ||
            (SELECT type_code FROM question_types WHERE id = NEW.question_type_id) ||
            ' (' || NEW.requirement || ')',
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 9. framework_links (INSERT only)
-- ============================================================

CREATE TRIGGER trg_activity_framework_links_insert
AFTER INSERT ON framework_links
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_framework_link', 'framework_link', NEW.id,
            'Linked frameworks: ' ||
            (SELECT name FROM frameworks WHERE id = NEW.from_framework_id) ||
            ' ' || NEW.link_type || ' ' ||
            (SELECT name FROM frameworks WHERE id = NEW.to_framework_id),
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 10. lectures (INSERT + UPDATE)
-- ============================================================

CREATE TRIGGER trg_activity_lectures_insert
AFTER INSERT ON lectures
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_lecture', 'lecture', NEW.id,
            'Added lecture ' || NEW.lecture_number || ': ' || NEW.title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

CREATE TRIGGER trg_activity_lectures_update
AFTER UPDATE ON lectures
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'updated_lecture', 'lecture', NEW.id,
            'Updated lecture ' || NEW.lecture_number || ': ' || NEW.title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 11. lecture_notes (INSERT only -- per request, no UPDATE)
-- ============================================================

CREATE TRIGGER trg_activity_lecture_notes_insert
AFTER INSERT ON lecture_notes
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (1, 'created_lecture_note', 'lecture_note', NEW.id,
            'Added ' || NEW.content_type || ' for lecture ' ||
            (SELECT lecture_number FROM lectures WHERE id = NEW.lecture_id) ||
            CASE WHEN NEW.section_title IS NOT NULL
                 THEN ': ' || NEW.section_title
                 ELSE '' END,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- 12. team_members (INSERT + UPDATE)
-- ============================================================

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

-- ============================================================
-- 13. tasks (INSERT + UPDATE)
-- ============================================================

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

-- ============================================================
-- 14. deliverables (INSERT only)
-- ============================================================

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

-- ============================================================
-- 15. hiring_candidates (INSERT + UPDATE)
-- ============================================================

CREATE TRIGGER trg_activity_hiring_candidates_insert
AFTER INSERT ON hiring_candidates
FOR EACH ROW
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (NEW.requested_by, 'created_hiring_candidate', 'hiring_candidate', NEW.id,
            'Opened hiring pipeline for: ' || NEW.role_title,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

CREATE TRIGGER trg_activity_hiring_candidates_update
AFTER UPDATE ON hiring_candidates
FOR EACH ROW
WHEN OLD.updated_at != NEW.updated_at
BEGIN
    INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, occurred_at)
    VALUES (NEW.requested_by, 'updated_hiring_candidate', 'hiring_candidate', NEW.id,
            'Hiring pipeline update: ' || NEW.role_title ||
            CASE WHEN OLD.stage != NEW.stage
                 THEN ' (stage: ' || OLD.stage || ' -> ' || NEW.stage || ')'
                 ELSE '' END,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
END;

-- ============================================================
-- Record this migration
-- ============================================================

INSERT INTO schema_versions (version, name, applied_at)
VALUES (5, '005_activity_triggers', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
