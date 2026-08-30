# LLM Call Logging Protocol (MANDATORY)

**Trigger:** After EVERY Agent tool call completes (success or failure).

Every agent invocation MUST be logged in the `llm_calls` table. The orchestrator is responsible for this as the **final step** of every delegation, with no exceptions.

## When to log

After EVERY Agent tool call completes (success or failure), the orchestrator MUST immediately log the call before doing anything else. This includes:
- Successful delegations
- Failed delegations (error details go to `activity_history`, see the Circuit Breaker protocol)
- Partial completions (agent hit maxTurns or was interrupted)

## What to log

The Agent tool returns `total_tokens`, `tool_uses`, and `duration_ms` in its output metadata. The orchestrator MUST extract these and insert into the database. Reference helper: `Database/helpers/log_llm_call.sql`.

## SQL template

```sql
INSERT INTO llm_calls (task_id, agent_name, model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, latency_ms, cost_usd)
VALUES (
    '{task_id}',            -- from tasks table, or 'ad-hoc' if no formal task
    '{agent_name}',         -- e.g., 'Maria', 'Sarah', 'Lena'
    '{model}',              -- must match a row in model_pricing
    {input_tokens_or_NULL}, -- exact value if known; NULL if unknown (NEVER 0 — see below)
    {output_tokens},        -- from Agent tool output (total_tokens is an acceptable lower bound)
    {cache_read_tokens},    -- 0 if not tracked
    {cache_write_tokens},   -- 0 if not tracked
    {duration_ms},          -- from Agent tool output
    NULL                    -- LET THE TRIGGER COMPUTE — do not hardcode 0
);
```

**Cost is auto-computed.** Migration `012_llm_cost_autocompute` adds an AFTER INSERT
trigger, `trg_llm_calls_autocost`, that fills `cost_usd` from the `model_pricing`
table whenever the inserted row has `cost_usd` NULL or 0. An explicitly supplied
non-zero cost is preserved verbatim. Pass `NULL` and let the database do the
arithmetic: hardcoding 0 silently under-reports spend, and a zero is
indistinguishable from a genuinely free call when you audit it months later.

If the model has no row in `model_pricing`, the trigger leaves `cost_usd` NULL
rather than writing a fake zero — the gap stays visible.

**Note:** the `llm_calls` table has NO `metadata` column. For failure details, log to
`activity_history` with `action = 'agent_failure'` (see the Circuit Breaker protocol).

## Cost reference — `model_pricing` is the source of truth

```sql
SELECT * FROM model_pricing;
```

Prices are USD per 1M tokens, seeded by migration 012 and updated as data, not as
a schema change. Add a row whenever you start using a new model — an unpriced
model shows up as `unpriced_model` in the quality view below.

**Formula the trigger applies:**
`cost_usd = (input * p_in + output * p_out + cache_read * p_cache_read + cache_write * p_cache_write) / 1_000_000`

## If exact token counts cannot be extracted

The Agent tool's usage block may give `total_tokens` and `duration_ms` without
splitting input from output. Until that gap closes:

- **Best path:** set `input_tokens = NULL` and put the full `total_tokens` in
  `output_tokens`. The trigger then computes a *conservative* lower-bound cost
  (output is the more expensive side), and the view `v_llm_calls_cost_quality`
  flags the row as `lower_bound_input_unknown`, so it is visible in audits.
- **Acceptable fallback:** with only `total_tokens`, split it 0.6 input / 0.4
  output. Still better than zeros.
- **NEVER** insert `input_tokens = 0, output_tokens = 0, cost_usd = 0` for a
  successful call — that hides spend behind a row that looks complete.
- **Failures:** for a genuinely failed delegation where the agent emitted nothing,
  `input_tokens = 0, output_tokens = 0` is honest (the trigger computes cost 0),
  and the failure detail goes to `activity_history` with `action = 'agent_failure'`.

Audit the honesty of the log with:

```sql
SELECT cost_quality, COUNT(*) FROM v_llm_calls_cost_quality GROUP BY cost_quality;
```

**Never skip logging.** A row with NULL token counts is better than no row at all —
the trigger and the cost-quality view will surface it for fixing. A row of zeros is
worse than either, because nothing surfaces it.
