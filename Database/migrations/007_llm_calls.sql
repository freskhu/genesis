-- Migration 007: LLM API cost and token usage tracking
-- Purpose: Track per-call LLM usage metrics for cost attribution,
--          budget monitoring, and performance analysis.
-- Date: 2026-04-06
-- Author: Lena (Database Architect)
--
-- Design notes:
--   - task_id is TEXT (not FK to tasks) because it references external
--     Claude Code task identifiers, not our internal task tracker.
--   - agent_name is a soft reference, not FK'd to team_members, because
--     agent names from Claude Code may not map 1:1 to our roster.
--   - cost_usd is REAL -- sufficient precision for observability data.
--   - cache_read_tokens and cache_write_tokens track prompt caching,
--     which significantly affects actual cost.

BEGIN TRANSACTION;

-- 1. Create the table
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

-- 2. Indexes for common query patterns
-- Cost attribution: "how much did each agent spend this week?"
CREATE INDEX idx_llm_calls_agent_created
    ON llm_calls (agent_name, created_at);

-- Per-task rollups: "what did this task cost in total?"
CREATE INDEX idx_llm_calls_task_id
    ON llm_calls (task_id);

-- 3. View: per-agent cost summary
CREATE VIEW v_agent_cost_summary AS
SELECT
    agent_name,
    COUNT(*)           AS total_calls,
    SUM(input_tokens)  AS total_input_tokens,
    SUM(output_tokens) AS total_output_tokens,
    SUM(cost_usd)      AS total_cost_usd,
    ROUND(AVG(latency_ms), 0) AS avg_latency_ms
FROM llm_calls
GROUP BY agent_name
ORDER BY total_cost_usd DESC;

-- 4. View: daily cost breakdown
CREATE VIEW v_daily_cost AS
SELECT
    DATE(created_at)   AS day,
    COUNT(*)           AS total_calls,
    SUM(input_tokens)  AS total_input_tokens,
    SUM(output_tokens) AS total_output_tokens,
    SUM(cache_read_tokens)  AS total_cache_read_tokens,
    SUM(cache_write_tokens) AS total_cache_write_tokens,
    SUM(cost_usd)      AS total_cost_usd,
    ROUND(AVG(latency_ms), 0) AS avg_latency_ms
FROM llm_calls
GROUP BY DATE(created_at)
ORDER BY day DESC;

-- 5. Record migration
INSERT INTO schema_versions (version, name, applied_at)
VALUES (7, '007_llm_calls', datetime('now'));

COMMIT;
