# LLM Call Logging Protocol (MANDATORY)

**Trigger:** After EVERY Agent tool call completes (success or failure).

Every agent invocation MUST be logged in the `llm_calls` table. The orchestrator is responsible for this as the **final step** of every delegation, with no exceptions.

## When to log

After EVERY Agent tool call completes (success or failure), the orchestrator MUST immediately log the call before doing anything else. This includes:
- Successful delegations
- Failed delegations (log with `cost_usd = 0`; error details go to `activity_history`, see Circuit Breaker protocol)
- Partial completions (agent hit maxTurns or was interrupted)

## What to log

The Agent tool returns `total_tokens`, `tool_uses`, and `duration_ms` in its output metadata. The orchestrator MUST extract these and insert into the database. Reference helper: `Database/helpers/log_llm_call.sql`.

## SQL template

```sql
INSERT INTO llm_calls (task_id, agent_name, model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, latency_ms, cost_usd)
VALUES (
    '{task_id}',           -- from tasks table or 'ad-hoc' if no formal task
    '{agent_name}',        -- e.g., 'Maria', 'Sarah', 'Lena'
    '{model}',             -- e.g., 'claude-opus-4', 'claude-sonnet-4'
    {input_tokens},        -- from Agent tool output, or estimated as total_tokens * 0.6
    {output_tokens},       -- from Agent tool output, or estimated as total_tokens * 0.4
    0,                     -- cache_read_tokens (not yet tracked at orchestrator level)
    0,                     -- cache_write_tokens (not yet tracked at orchestrator level)
    {duration_ms},         -- from Agent tool output
    {cost_usd}             -- estimated: see cost table below
);
```

**Note:** The `llm_calls` table has NO `metadata` column. For failure details, log to `activity_history` with `action = 'agent_failure'` (see Circuit Breaker protocol). For success logging, the token/cost/latency fields are sufficient.

## Cost estimation reference

| Model | Input $/M tokens | Output $/M tokens |
|-------|-------------------|---------------------|
| opus  | 15.00             | 75.00               |
| sonnet| 3.00              | 15.00               |
| haiku | 0.25              | 1.25                |

**Formula:** `cost_usd = (input_tokens * input_rate + output_tokens * output_rate) / 1_000_000`

## If exact token counts cannot be extracted

Estimate conservatively:
- `input_tokens = total_tokens * 0.6`
- `output_tokens = total_tokens * 0.4`
- If no token data available at all: log with `input_tokens = 0, output_tokens = 0, cost_usd = 0`

**Never skip logging. A row with zeros is better than no row at all.**
