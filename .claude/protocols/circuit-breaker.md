# Circuit Breaker Protocol (MANDATORY)

**Trigger:** Agent returns an error, empty result, or clearly wrong output.

## Failure Handling Rules

When an agent returns an error, empty result, or clearly wrong output:

1. **First failure:** The orchestrator MUST analyze the error, identify the likely cause, adjust the prompt or approach, and relaunch with the fix. Log the failure in `activity_history`. **When retrying, the orchestrator MUST include the previous failure context in the new prompt:**
   > "PREVIOUS ATTEMPT FAILED. Here is what happened:
   > - Error: {error_description}
   > - What was tried: {approach_description}
   > - Likely cause: {root_cause_analysis}
   > Do NOT repeat the same approach. Adjust your strategy based on this failure."
2. **Second failure (same agent, same task):** The orchestrator MUST try a different strategy -- different prompt structure, different agent, or decompose the task into smaller sub-tasks. Log the failure.
3. **Third failure (same agent, same task):** The orchestrator MUST STOP and escalate to the user with a diagnostic report:
   - What was attempted (3 times)
   - What errors occurred each time
   - What the orchestrator thinks the root cause is
   - Recommended next steps (manual intervention, different approach, skip)

**The orchestrator MUST NOT blindly relaunch the same agent with the same prompt after a failure.** Every retry MUST include a visible change to the approach.

## Failure Logging

Every agent failure MUST be logged in `activity_history`:

```sql
INSERT INTO activity_history (actor_id, action, entity_type, entity_id, summary, metadata)
VALUES (
    1,                          -- orchestrator's actor_id
    'agent_failure',
    'task',
    {task_id_or_null},
    'Agent {name} failed on {task_description}: {error_summary}',
    '{"agent": "{name}", "attempt": {N}, "error": "{error_detail}", "next_action": "{retry|escalate}"}'
);
```

## Failure Pattern Detection

After logging a failure, the orchestrator MUST check for systemic issues:

```sql
SELECT json_extract(metadata, '$.agent') AS agent,
       COUNT(*) AS recent_failures
FROM activity_history
WHERE action = 'agent_failure'
  AND occurred_at > datetime('now', '-24 hours')
GROUP BY json_extract(metadata, '$.agent')
HAVING COUNT(*) >= 3;
```

If any agent has 3+ failures in 24h, flag to the user: "{agent_name} had {recent_failures} failures in the last 24h. There may be a systemic problem."
