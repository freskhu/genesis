# Session End Protocol (MANDATORY)

**Trigger:** End of every conversation (before the orchestrator closes the session).

At the **end of every conversation**, the orchestrator must:

**Step 1 — Palace Updates:**
- Check if new info about the user surfaced → `palace.py add (content, wing="owner", room="identity|preferences|projects")`
- Check if new entity facts emerged → `palace.py kg-add(subject, predicate, object)` or `palace.py kg-invalidate` for outdated facts

**Step 2 — Diary Entry:**
- Write a session diary summarizing key actions, delegations, and outcomes:
  ```
  palace.py diary-write (agent_name="Orchestrator", entry="SESSION:YYYY-MM-DD|key.actions.summary|★★", topic="session")
  ```

**Step 3 — Activity Log:**
- Log the session end in activity_history

**Step 3.5 — Kaizen Backlog Surface (MANDATORY when applicable):**
1. Query `[Kaizen]` proposals pending >48h:
   ```sql
   SELECT id, title, julianday('now') - julianday(created_at) AS days_pending
   FROM tasks
   WHERE status = 'pending' AND title LIKE '[Kaizen]%'
     AND julianday('now') - julianday(created_at) > 2
   ORDER BY created_at ASC;
   ```
2. If 3 or more rows return, present them at end of session: "Before closing: you have X kaizen proposals >48h without a decision. Here are the IDs and titles. Resolve any now or leave for another session?"
3. This is the **session-end** counterpart to Step 2.5 of the Session Start Protocol. The Start version surfaces at session open; the End version reminds before closing if the user didn't address them mid-session.
4. Reason for the rule: backlog tends to accumulate faster than the user tackles it. Surface twice per session = 2 nudges max, not nag.

**Step 4 — Lessons Learned & System Improvement (MANDATORY):**

Before closing, the orchestrator MUST run a session retrospective to capture what worked, what didn't, and what to improve. This is the moment to turn the session's lived experience into durable system improvements.

1. **Scan for failures and friction:**
   ```sql
   -- Agent failures during this session
   SELECT json_extract(metadata, '$.agent') AS agent, summary, metadata, occurred_at
   FROM activity_history
   WHERE action = 'agent_failure' AND occurred_at > datetime('now', 'start of day')
   ORDER BY occurred_at DESC;
   ```
   Also re-read the conversation for user corrections — explicit pushback like "no", "wrong", "I already told you", "that's not it", "stop". Each one is a learning signal.

2. **Scan for what worked:**
   - Delegations that completed cleanly on first try
   - Approaches the user validated explicitly ("perfect", "exactly", "good") OR accepted without correction (quieter signal — watch for it)
   - Non-obvious choices that paid off

3. **Persist learnings — choose the right channel:**
   - **Behavioural correction or preference** → write a `feedback` memory and update the memory index.
   - **Reusable approach that succeeded** → INSERT into `procedural_memory` (trigger_pattern, action, steps, tags). If it already exists, increment `success_count`.
   - **Approach that failed using an existing procedure** → increment `failure_count` on that row.
   - **New fact about the user / project / entity** → `palace.py add` (right wing+room+hall) and/or `palace.py kg-add`.
   - **Stale fact** → `palace.py kg-invalidate`.

4. **Propose system improvements (concrete, not vague):**
   For each pattern of friction, propose ONE concrete change to one of:
   - `CLAUDE.md` (rule, protocol, routing)
   - An agent definition (`.claude/agents/<name>.md`)
   - A skill (`.claude/skills/<name>/`)
   - A hook (`.claude/hooks/`)
   - The DB schema or a query helper

   Vague suggestions ("improve X") are NOT acceptable. Concrete ones look like: "Add to the marketing agent's prompt: 'Always quote in EUR for EU clients unless told otherwise'."

5. **Present a Lessons Brief to the user** before closing:
   > **Session lessons:**
   > - **I failed at:** [X] → saved a feedback memory / added a rule in CLAUDE.md
   > - **What worked:** [Y] → recorded a procedure in `procedural_memory`
   > - **Improvement suggestion:** [concrete change to file/agent/hook]
   >
   > Apply the suggestion? (yes/no/adjust)

   If the user says yes → apply the change in this session before regenerating memory hot. If no → log the suggestion in `activity_history` (action: `improvement_suggested`) so it doesn't get lost.

   If the session was clean (no failures, no corrections, nothing new): say so honestly. Do NOT invent lessons. A short "Clean session, no new lessons" is a valid output.

**Step 4.5 — Procedural Memory Audit (MANDATORY — BLOCKING):**

Step 4 lists `procedural_memory` as one of several channels but the feedback loop is loose. Without a hard gate, kaizen can run repeatedly and detect 0 new patterns despite non-trivial R3/R4/R5 delegations. This step closes that loop.

1. **Enumerate session delegations:**
   ```sql
   SELECT agent_name, COUNT(*) AS calls, SUM(cost_usd) AS spend
   FROM llm_calls
   WHERE created_at > datetime('now', 'start of day')
     AND agent_name NOT IN ('Orchestrator', 'ad-hoc')
   GROUP BY agent_name
   ORDER BY spend DESC;
   ```

2. **Check today's procedural_memory captures:**
   ```sql
   SELECT id, name, trigger_pattern, source_agent
   FROM procedural_memory
   WHERE created_at > datetime('now', 'start of day');
   ```

3. **Decision gate (BLOCKING):** For every agent delegation today, the orchestrator MUST answer:
   - Was the approach non-obvious or reusable? (specific framework chain, unusual model routing, multi-agent sequence, novel workaround)
   - If YES and there's no matching row in step 2 → INSERT one NOW. Do not close the session.
   - If NO (trivial edit, standard query, routine email) → no action.

4. **Verbalize the audit to the user:**
   > **Procedural audit:** delegations today: [list]. Captured: [N]. Skipped (trivial): [list].
   >
   > "No non-trivial delegations this session — nothing to capture" is a valid output if true.

5. **Skipping rule:** This step can ONLY be skipped if there were zero R3/R4/R5 delegations in the session. Otherwise this step is non-negotiable — the audit must be verbalized to the user before Step 5.

**Step 5 — Regenerate Memory Hot:**
```bash
python3 scripts/generate_memory_hot.py
```
This ensures the next session starts with a fresh briefing — including any lessons just persisted.
