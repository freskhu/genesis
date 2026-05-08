-- log_llm_call.sql
-- Template INSERT for logging LLM agent invocations.
-- the orchestrator (orchestrator) MUST execute this after every Agent tool delegation.
--
-- Usage: Replace {placeholders} with actual values from the Agent tool output.
-- All numeric placeholders default to 0 if data is unavailable.
--
-- Required PRAGMAs (set once per connection):
--   PRAGMA foreign_keys = ON;
--   PRAGMA journal_mode = WAL;
--   PRAGMA busy_timeout = 5000;
--   PRAGMA synchronous = NORMAL;

INSERT INTO llm_calls (
    task_id,
    agent_name,
    model,
    input_tokens,
    output_tokens,
    cache_read_tokens,
    cache_write_tokens,
    latency_ms,
    cost_usd
) VALUES (
    '{task_id}',              -- TEXT: task ID from tasks table, or 'ad-hoc'
    '{agent_name}',           -- TEXT: agent name (e.g., 'Researcher', 'DBA')
    '{model}',                -- TEXT: 'claude-opus-4-6', 'claude-sonnet-4', or 'claude-haiku-3'
    {input_tokens},           -- INTEGER: from Agent output, or total_tokens * 0.6
    {output_tokens},          -- INTEGER: from Agent output, or total_tokens * 0.4
    {cache_read_tokens},      -- INTEGER: 0 if not tracked
    {cache_write_tokens},     -- INTEGER: 0 if not tracked
    {duration_ms},            -- INTEGER: from Agent tool output
    {cost_usd}                -- REAL: (input * rate_in + output * rate_out) / 1000000
);

-- ============================================================
-- NOTE: The llm_calls table has NO metadata column.
-- For failure details, log to activity_history with
-- action = 'agent_failure' (see Circuit Breaker in CLAUDE.md).
-- ============================================================
--
-- ============================================================
-- COST RATE TABLE (as of 2026-04-06)
-- ============================================================
--
-- Model        | Input $/M tokens | Output $/M tokens
-- -------------|------------------|------------------
-- opus         | 15.00            | 75.00
-- sonnet       |  3.00            | 15.00
-- haiku        |  0.25            |  1.25
--
-- Cache read:  90% discount on input price
-- Cache write: 25% surcharge on input price
--
-- Formula: cost_usd = (input_tokens * input_rate + output_tokens * output_rate) / 1000000
--
-- ============================================================
-- MONITORING VIEWS (already exist in team.db)
-- ============================================================
--
-- v_agent_cost_summary: per-agent totals (calls, tokens, cost, avg latency)
-- v_daily_cost: daily breakdown (calls, tokens, cache usage, cost, avg latency)
--
-- Quick check:
-- SELECT * FROM v_agent_cost_summary;
-- SELECT * FROM v_daily_cost;
