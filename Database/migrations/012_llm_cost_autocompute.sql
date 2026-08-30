-- Migration 012: Auto-compute cost_usd on llm_calls rows
-- Purpose: Stop systematic under-reporting of LLM spend caused by callers
--          inserting llm_calls rows with cost_usd=0 hardcoded. Introduces a
--          per-model pricing reference table and an AFTER INSERT trigger that
--          fills cost_usd from token counts when the caller did not supply it.
-- Author: the database architect agent
--
-- Design notes:
--   - SQLite BEFORE INSERT triggers cannot assign to NEW.col (that's MySQL
--     syntax). The portable SQLite pattern is an AFTER INSERT trigger that
--     issues an UPDATE on the same row, guarded by a WHEN clause so it only
--     fires when the caller passed cost_usd=0 or NULL. An explicit non-zero
--     cost_usd is preserved verbatim — we never trample a measured value.
--   - Prices live in a dedicated `model_pricing` table (USD per 1M tokens)
--     so price changes are a data update, not a schema migration. The trigger
--     joins against it via correlated subqueries; rows with no matching model
--     fall back to a NULL cost (rather than silently zero) so the gap is
--     visible in reports.
--   - Cache pricing: Anthropic charges cache writes at +25% of input price and
--     cache reads at -90% of input price. We store these explicitly to avoid
--     baking the multipliers into the trigger.
--   - Pricing values seeded here are Anthropic published list prices at the time
--     this migration was written. Verify them against your own commercial rates,
--     and add a row for every model you actually use: an unpriced model yields a
--     NULL cost, which is visible, rather than a zero, which is not.
--   - Migration is additive: no existing columns dropped or renamed.

BEGIN TRANSACTION;

-- 1. Pricing reference table -------------------------------------------------
CREATE TABLE IF NOT EXISTS model_pricing (
    model                   TEXT PRIMARY KEY,
    input_per_m_usd         REAL NOT NULL,
    output_per_m_usd        REAL NOT NULL,
    cache_read_per_m_usd    REAL,
    cache_write_per_m_usd   REAL,
    effective_from          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    notes                   TEXT
);

-- 2. Seed current Anthropic prices (USD per 1M tokens) -----------------------
--    Opus 4.x:    $15 in / $75 out / $1.50 cache_read / $18.75 cache_write
--    Sonnet 4.x:  $3 in  / $15 out / $0.30 cache_read / $3.75 cache_write
--    Haiku 4.x:   $1 in  / $5 out  / $0.10 cache_read / $1.25 cache_write
INSERT OR REPLACE INTO model_pricing
    (model, input_per_m_usd, output_per_m_usd, cache_read_per_m_usd, cache_write_per_m_usd, notes)
VALUES
    ('claude-opus-4-7',          15.00, 75.00, 1.50,  18.75, 'Anthropic list price; verify vs your commercial rate'),
    ('claude-opus-4-6',          15.00, 75.00, 1.50,  18.75, 'Anthropic list price; verify vs your commercial rate'),
    ('claude-sonnet-4-6',         3.00, 15.00, 0.30,   3.75, 'Anthropic list price'),
    ('claude-sonnet-4',           3.00, 15.00, 0.30,   3.75, 'Anthropic list price'),
    ('claude-haiku-4-5-20251001', 1.00,  5.00, 0.10,   1.25, 'Anthropic list price'),
    ('claude-haiku-3',            0.25,  1.25, 0.025,  0.30, 'Legacy Haiku 3 pricing');

-- 3. Auto-cost trigger -------------------------------------------------------
--    Fires AFTER INSERT only when the caller left cost_usd at 0 or NULL.
--    Reads pricing from model_pricing; if model is unknown, sets cost to NULL
--    so the absence is auditable (vs. fake zero).
CREATE TRIGGER trg_llm_calls_autocost
AFTER INSERT ON llm_calls
FOR EACH ROW
WHEN (NEW.cost_usd IS NULL OR NEW.cost_usd = 0)
BEGIN
    UPDATE llm_calls
    SET cost_usd = (
        SELECT
            ( COALESCE(NEW.input_tokens, 0)        * p.input_per_m_usd
            + COALESCE(NEW.output_tokens, 0)       * p.output_per_m_usd
            + COALESCE(NEW.cache_read_tokens, 0)   * COALESCE(p.cache_read_per_m_usd, 0)
            + COALESCE(NEW.cache_write_tokens, 0)  * COALESCE(p.cache_write_per_m_usd, 0)
            ) / 1000000.0
        FROM model_pricing p
        WHERE p.model = NEW.model
    )
    WHERE id = NEW.id;
END;

-- 4. Helper view: rows whose cost is a lower-bound estimate ------------------
--    A row is "lower-bound" when input_tokens is NULL (token count unknown)
--    OR when input_tokens = 0 alongside a non-zero output. Useful for kaizen
--    audits and to flag work upstream (extracting real input_tokens).
CREATE VIEW IF NOT EXISTS v_llm_calls_cost_quality AS
SELECT
    id,
    created_at,
    agent_name,
    model,
    input_tokens,
    output_tokens,
    cost_usd,
    CASE
        WHEN input_tokens IS NULL                       THEN 'lower_bound_input_unknown'
        WHEN input_tokens = 0 AND output_tokens > 0     THEN 'lower_bound_input_zero'
        WHEN cost_usd IS NULL                           THEN 'unpriced_model'
        ELSE 'measured'
    END AS cost_quality
FROM llm_calls;

-- 5. Record migration --------------------------------------------------------
INSERT INTO schema_versions (version, name, applied_at)
VALUES (12, '012_llm_cost_autocompute', strftime('%Y-%m-%dT%H:%M:%SZ','now'));

COMMIT;
