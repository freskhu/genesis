-- Migration 027 -- spec_criteria: machine-readable acceptance criteria
--
-- What: one row per acceptance criterion of a spec in Team/_briefs/. A criterion is a
-- `- [ ]` box under the spec's "## Acceptance criteria" heading. The state lives here, not
-- in the file: the boxes in the file are a derived view, ticked only by
-- `scripts/spec_criteria.py close`.
--
-- Life cycle:
--   fail ──claim──> claimed ──verify──> verified
--     │               │  └──fail──> fail          (verify refused, or reopened)
--     └──waive──> waived                          (only with the owner's decision quoted)
--   any non-terminal ──> superseded               (text changed in the file: new row)
--
-- The author points at the proof (`claim --evidence`); someone else verifies it. The
-- triggers below enforce, in the data, what the script also checks:
--   1. rows are born as `fail`;
--   2. status transitions follow the whitelist above;
--   3. the verifier is neither the author nor whoever claimed;
--   4. text, text_hash and spec_path never change (a new text is a new criterion);
--   5. the author, once set, does not change;
--   6. rows are never deleted.
--
-- Writes go through scripts/spec_criteria.py only. .claude/hooks/sql-guardrails.sh blocks
-- direct INSERT/UPDATE/REPLACE and DDL on this table from the shell.
--
-- Requires SQLite 3.37+ (STRICT tables).
-- Apply:    sqlite3 Database/team.db < Database/migrations/027_spec_criteria.sql
-- Rollback: Database/migrations/027_rollback_spec_criteria.sql

PRAGMA foreign_keys = ON;

BEGIN;

CREATE TABLE spec_criteria (
    id           INTEGER PRIMARY KEY,
    spec_path    TEXT    NOT NULL
                 CHECK (spec_path GLOB 'Team/_briefs/*.md'
                        AND length(spec_path) <= 300
                        AND spec_path NOT LIKE '%..%'),
    ordinal      INTEGER NOT NULL CHECK (ordinal >= 1),       -- position at last ingest
    text         TEXT    NOT NULL CHECK (trim(text) <> '' AND length(text) <= 2000),
    text_hash    TEXT    NOT NULL
                 CHECK (length(text_hash) = 64 AND text_hash NOT GLOB '*[^0-9a-f]*'),
    redacted     INTEGER NOT NULL DEFAULT 0 CHECK (redacted IN (0, 1)),
    source_line  INTEGER CHECK (source_line IS NULL OR source_line >= 1),
    status       TEXT    NOT NULL DEFAULT 'fail'
                 CHECK (status IN ('fail', 'claimed', 'verified', 'waived', 'superseded')),
    author       TEXT,                                         -- agent dispatched with the spec
    claimed_by   TEXT,
    claimed_at   TEXT,
    evidence     TEXT    CHECK (evidence IS NULL
                                OR (trim(evidence) <> '' AND length(evidence) <= 1000)),
    verified_by  TEXT,
    verified_at  TEXT,
    note         TEXT    CHECK (note IS NULL OR length(note) <= 2000),
    created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE (spec_path, text_hash),
    CHECK (status <> 'claimed'  OR (claimed_by IS NOT NULL AND claimed_at IS NOT NULL
                                    AND evidence IS NOT NULL)),
    CHECK (status <> 'verified' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL
                                    AND evidence IS NOT NULL)),
    CHECK (status <> 'waived'   OR note IS NOT NULL)
) STRICT;

CREATE INDEX idx_spec_criteria_spec ON spec_criteria (spec_path, status);

-- 1. Born as fail.
CREATE TRIGGER trg_spec_criteria_born_fail
BEFORE INSERT ON spec_criteria
WHEN NEW.status <> 'fail'
BEGIN
    SELECT RAISE(ABORT, 'spec_criteria: rows are born as fail');
END;

-- 2. Transition whitelist. superseded is terminal.
CREATE TRIGGER trg_spec_criteria_transition
BEFORE UPDATE OF status ON spec_criteria
WHEN OLD.status <> NEW.status
 AND NOT (
      (OLD.status = 'fail'     AND NEW.status IN ('claimed', 'waived', 'superseded'))
   OR (OLD.status = 'claimed'  AND NEW.status IN ('verified', 'fail', 'waived', 'superseded'))
   OR (OLD.status = 'verified' AND NEW.status IN ('fail', 'superseded'))
   OR (OLD.status = 'waived'   AND NEW.status IN ('fail', 'superseded'))
 )
BEGIN
    SELECT RAISE(ABORT, 'spec_criteria: status transition not allowed');
END;

-- 3. Whoever verifies did not author or claim.
CREATE TRIGGER trg_spec_criteria_verifier
BEFORE UPDATE ON spec_criteria
WHEN NEW.status = 'verified' AND OLD.status <> 'verified'
 AND (lower(NEW.verified_by) = lower(COALESCE(NEW.claimed_by, ''))
      OR lower(NEW.verified_by) = lower(COALESCE(NEW.author, '')))
BEGIN
    SELECT RAISE(ABORT, 'spec_criteria: the verifier cannot be the author or the claimer');
END;

-- 4. Text, hash and spec path are immutable.
CREATE TRIGGER trg_spec_criteria_immutable
BEFORE UPDATE OF text, text_hash, spec_path, redacted ON spec_criteria
WHEN NEW.text IS NOT OLD.text OR NEW.text_hash IS NOT OLD.text_hash
  OR NEW.spec_path IS NOT OLD.spec_path OR NEW.redacted IS NOT OLD.redacted
BEGIN
    SELECT RAISE(ABORT, 'spec_criteria: text, hash and spec path are immutable');
END;

-- 5. The author, once set, stays.
CREATE TRIGGER trg_spec_criteria_author_fixed
BEFORE UPDATE OF author ON spec_criteria
WHEN OLD.author IS NOT NULL AND NEW.author IS NOT OLD.author
BEGIN
    SELECT RAISE(ABORT, 'spec_criteria: the author does not change');
END;

-- 6. No deletes.
CREATE TRIGGER trg_spec_criteria_no_delete
BEFORE DELETE ON spec_criteria
BEGIN
    SELECT RAISE(ABORT, 'spec_criteria: rows are never deleted; use superseded');
END;

INSERT INTO schema_versions (version, name) VALUES (27, 'spec_criteria');

COMMIT;
