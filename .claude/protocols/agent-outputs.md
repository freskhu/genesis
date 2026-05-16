# Mandatory Agent Outputs

**Trigger:** Before delegating to any agent (R3/R4/R5). These instructions MUST be included in the agent prompt.

Every agent delegation (R3/R4/R5) MUST include these instructions in the agent prompt:

1. **Handoff summary** — at the end of the work, the agent must output a clear handoff:
   > "HANDOFF: What was done: [summary]. What was decided: [decisions]. What's left: [remaining work]. Blockers: [if any]."
   The orchestrator captures this from the agent result and logs key points in `activity_history`.

2. **KG facts** — if the agent discovers new entity relationships, it must output them:
   > "KG-FACTS: [Subject] → [predicate] → [Object] (valid_from: [date])"
   The orchestrator then adds these via `palace.py kg-add`. If facts changed, agent outputs:
   > "KG-INVALIDATE: [Subject] → [predicate] → [Object]"

3. **Diary entry** — for significant work, the agent must write its own diary:
   > `palace.py diary-write (agent_name='AgentName', entry='AAAK summary', topic='topic')`

The orchestrator is responsible for extracting handoff and KG-facts from agent results and persisting them. Agents that don't produce a handoff summary should be re-prompted: "Provide your handoff: what was done, what was decided, what's left."

**Procedural memory capture (MANDATORY post-delegation):** After a successful R3/R4/R5 delegation where the approach was **non-obvious or reusable** (e.g., a specific framework chain, an unusual model routing, a multi-agent sequence that solved a tricky problem), the orchestrator MUST insert a row into `procedural_memory` BEFORE closing the task. This builds institutional learning — patterns that worked once get reused. If the approach was trivial/obvious (one-liner edit, standard query, routine email), skip this step. Reason for the rule: without a feedback loop, kaizen can run repeatedly and detect 0 new patterns despite multiple successful non-obvious delegations.
