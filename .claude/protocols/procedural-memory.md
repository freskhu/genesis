# Procedural Memory (Institutional Learning)

**Trigger:** Before delegating (query existing patterns) AND after successful non-trivial delegation (record new pattern).

The `procedural_memory` table stores successful patterns that agents discover. This creates institutional learning — what worked once gets reused.

## When to RECORD a procedure (after successful agent completion)

After an agent completes a task successfully, the orchestrator MUST check if the approach was non-obvious or reusable. If yes:

```sql
INSERT INTO procedural_memory (trigger_pattern, action, success_count, source_agent, last_used_at, name, steps, context_requirements, tags)
VALUES (
    '{what_triggers_this_pattern}',   -- e.g., 'multi-source research synthesis'
    '{what_to_do}',                    -- e.g., 'Use Maria with scope -> sources -> synthesis chain'
    1,                                 -- first success
    '{agent_name}',
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
    '{short_name}',
    '{step1 -> step2 -> step3}',
    '{what_context_is_needed}',
    '{comma,separated,tags}'
);
```

## When to QUERY procedures (before delegating)

Before delegating a task (R3/R4/R5), the orchestrator MUST check for matching procedures:

```sql
SELECT name, action, steps, success_count, failure_count, success_rate, source_agent
FROM procedural_memory
WHERE trigger_pattern LIKE '%keyword%' OR tags LIKE '%keyword%'
ORDER BY success_rate DESC, success_count DESC
LIMIT 3;
```

If a matching procedure exists with `success_rate > 0.7`, include it in the agent prompt:
> "PROVEN PROCEDURE (success_rate: {rate}): {steps}. Follow this approach unless you have a strong reason to deviate."

## When to UPDATE counters

- Agent succeeds using the procedure → `UPDATE procedural_memory SET success_count = success_count + 1, last_used_at = ... WHERE id = {id}`
- Agent fails using the procedure → `UPDATE procedural_memory SET failure_count = failure_count + 1 WHERE id = {id}`

## Kaizen reviews procedures

During `/kaizen`, check for procedures with low success rates:
```sql
SELECT name, success_rate, success_count + failure_count AS total_uses
FROM procedural_memory
WHERE success_rate < 0.5 AND (success_count + failure_count) >= 3;
```
Flag these to the user for review or deletion.
