-- ============================================================================
-- Migration 023 -- actor_id guardrail on activity_history
-- Author: the database architect agent
-- ============================================================================
--
-- PROBLEM
-- -------
-- A row landed in activity_history with actor_id = 'SomeAgentName' (text)
-- instead of the numeric id. The column already declares the foreign key:
--
--     actor_id INTEGER NOT NULL REFERENCES team_members(id) ON DELETE RESTRICT
--
-- In SQLite that FK is only checked when the CONNECTION runs
-- PRAGMA foreign_keys = ON. The house rule requires it on every connection, but
-- enforcement is by convention: whoever writes has to remember. Most writes to
-- activity_history are ad-hoc INSERTs an agent composes from templates in
-- .claude/protocols/ and .claude/skills/, and most of those templates do not
-- carry the PRAGMA. A connection without it accepts the name silently: INTEGER
-- affinity cannot convert a name to an integer, so the value is stored as TEXT,
-- and the violation only surfaces later in a PRAGMA foreign_key_check.
--
-- CHOICE
-- ------
-- A BEFORE INSERT / BEFORE UPDATE trigger with RAISE(ABORT), rather than (or
-- ahead of) a write helper. Reason: triggers run inside the engine, are
-- independent of the connection's PRAGMA state, and apply to EVERY write path --
-- including the ones nobody anticipated and the ones that arrive through other
-- triggers. A helper protects only the callers who remember to use it, which is
-- exactly the original failure mode. Keep the helper as a convenience layer, not
-- as the defence.
--
-- The general shape: when a rule depends on every caller remembering a setting,
-- the rule is not enforced. Move it to where it cannot be skipped.
--
-- Cost: the trigger's message replaces SQLite's FK message, and a bad INSERT now
-- fails always instead of failing only when the PRAGMA happens to be on. That is
-- the point -- loud immediate failure instead of silent corruption discovered
-- weeks later.
--
-- COMPATIBILITY
-- -------------
-- Before applying, verify your own data:
--     SELECT COUNT(*) FROM activity_history WHERE typeof(actor_id) <> 'integer';
--     PRAGMA foreign_key_check(activity_history);
-- Both must come back empty. The activity triggers from migrations 005 and 006
-- write valid ids (literal 1, NEW.processed_by via COALESCE, or a NEW.id from a
-- team_members row already inserted), so they pass the check.
--
-- ROLLBACK
-- --------
--     DROP TRIGGER trg_activity_history_actor_guard_insert;
--     DROP TRIGGER trg_activity_history_actor_guard_update;
--     DELETE FROM schema_versions WHERE version = 23;
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- INSERT guardrail.
--
-- Three rejection conditions, ordered by cost:
--   1. actor_id NULL -- redundant with the column's NOT NULL, but yields a
--      useful message instead of "NOT NULL constraint failed".
--   2. typeof(actor_id) <> 'integer' -- catches a name, and any other text that
--      will not convert. Note: a well-formed '7' is converted by column affinity
--      to the integer 7 before the trigger runs, so typeof returns 'integer' and
--      it is not rejected -- correct, because 7 is a valid id.
--   3. actor_id with no matching team_members row -- what the FK would have
--      guaranteed, now without depending on the PRAGMA.
-- ---------------------------------------------------------------------------
CREATE TRIGGER trg_activity_history_actor_guard_insert
    BEFORE INSERT ON activity_history
    FOR EACH ROW
    WHEN NEW.actor_id IS NULL
         OR typeof(NEW.actor_id) <> 'integer'
         OR NOT EXISTS (SELECT 1 FROM team_members WHERE id = NEW.actor_id)
BEGIN
    SELECT RAISE(ABORT,
        'activity_history.actor_id is invalid: it must be an existing numeric team_members.id. Resolve the name to an id -- (SELECT id FROM team_members WHERE name = ''<agent>'') -- instead of writing the name or a hardcoded id.');
END;

-- ---------------------------------------------------------------------------
-- Symmetric UPDATE guardrail.
--
-- Without it, one badly written repair UPDATE reintroduces exactly the defect the
-- INSERT guard now blocks. The WHEN clause includes
-- OLD.actor_id IS NOT NEW.actor_id so the EXISTS is not paid on UPDATEs that only
-- touch summary/metadata (the common case).
-- ---------------------------------------------------------------------------
CREATE TRIGGER trg_activity_history_actor_guard_update
    BEFORE UPDATE OF actor_id ON activity_history
    FOR EACH ROW
    WHEN OLD.actor_id IS NOT NEW.actor_id
         AND (NEW.actor_id IS NULL
              OR typeof(NEW.actor_id) <> 'integer'
              OR NOT EXISTS (SELECT 1 FROM team_members WHERE id = NEW.actor_id))
BEGIN
    SELECT RAISE(ABORT,
        'activity_history.actor_id is invalid on UPDATE: it must be an existing numeric team_members.id.');
END;

INSERT INTO schema_versions (version, name)
VALUES (23, '023_activity_actor_guardrail');

COMMIT;
