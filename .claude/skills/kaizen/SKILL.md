---
name: kaizen
description: "Continuous improvement review: system health, failure review, procedural learning, and 1-3 concrete improvement proposals. Supports --auto for unattended scheduled runs."
user-invocable: true
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep"]
---

# Kaizen — Continuous Improvement

## Modes

| Mode | Trigger | Behaviour |
|------|---------|-----------|
| **Interactive** (default) | `/kaizen` from a normal session | Run all phases, present the report and the proposals to the user, never auto-implement. |
| **Auto** | `/kaizen --auto` from a scheduler | Run all phases unattended. Suppress every step that would ask the user. Write the full report to a dated file and touch the sentinel at the end. |

In `--auto` mode, NEVER pause for input. Where a step would normally ask the
user, append the question and the assumed default to the report under "Open
questions", and carry on.

## When to run

Pick a cadence and hold it. Daily works while the system is young and changing
fast; weekly is enough once it settles. A review that runs more often than there
is new evidence to review produces proposals padded out to fill the slot.

- **Scheduled** — via a launch agent, cron, or your scheduler of choice, in
  `--auto` mode.
- **Manually** — when the user asks for a system review.

## Check whether it already ran

```sql
PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;
SELECT MAX(occurred_at) AS last_run FROM activity_history
WHERE action = 'kaizen_completed';
```

If the last run falls inside the current period, skip. The sentinel file (see the
end of this skill) is the cheap version of the same check, for the wrapper.

**Long-gap detection:** if the last run is much older than the cadence, say so at
the top of the report and widen every "since last kaizen" window accordingly.
Otherwise the run silently reviews a 24-hour slice of a three-week gap and reports
that everything is fine.

## Phase 1 — System health

Run the `/db-health` checks and score them with the same rubric. Do not duplicate
the SQL here: `.claude/skills/db-health/SKILL.md` is the source of truth, and two
copies of a health rubric drift apart within a month.

Additionally, check that the skills on disk still match what the protocols
describe:

```bash
ls .claude/skills/*/SKILL.md
```

For any skill whose referenced tables, scripts or agent names no longer exist,
that is a finding — a skill that names a missing dependency fails at the moment
someone actually needs it.

## Phase 2 — Failure review (since the last kaizen)

```sql
-- Agent failures
SELECT json_extract(metadata, '$.agent') AS agent,
       json_extract(metadata, '$.error') AS error,
       summary,
       occurred_at
FROM activity_history
WHERE action = 'agent_failure'
  AND occurred_at > COALESCE(
    (SELECT MAX(occurred_at) FROM activity_history WHERE action = 'kaizen_completed'),
    datetime('now', '-7 days'))
ORDER BY occurred_at DESC;

-- Calls logged with no cost: unpriced model, or broken logging
SELECT agent_name, model, COUNT(*) AS n
FROM llm_calls
WHERE (cost_usd IS NULL OR cost_usd = 0)
  AND created_at > datetime('now', '-7 days')
GROUP BY agent_name, model;
```

For each failure pattern: what went wrong, is it recurring, and what should change
(prompt adjustment, different agent, new skill, new guardrail).

## Phase 3 — Procedural memory review

```sql
-- Patterns with a low success rate
SELECT id, name, trigger_pattern, success_count, failure_count, success_rate
FROM procedural_memory
WHERE success_rate < 0.5 AND (success_count + failure_count) >= 3
ORDER BY success_rate ASC;

-- New patterns since the last kaizen
SELECT id, name, trigger_pattern, created_at
FROM procedural_memory
WHERE created_at > COALESCE(
  (SELECT MAX(occurred_at) FROM activity_history WHERE action = 'kaizen_completed'),
  '2000-01-01');

-- Patterns that have earned the reliable bar
SELECT id, name, action, success_rate, success_count
FROM procedural_memory
WHERE success_rate >= 0.8 AND success_count >= 3
ORDER BY success_rate DESC;

-- Loop health: rows that can never be incremented again
SELECT COUNT(*) AS unreachable_orphans FROM procedural_memory WHERE dedup_key IS NULL;
```

Two numbers matter more than the totals: how many patterns are still stuck at
`success_count <= 1`, and whether `unreachable_orphans` is growing. The first says
patterns are captured but never recorded as reused; the second says someone is
still writing INSERTs by hand.

## Phase 3.5 — Knowledge-graph contradiction detection

```sql
-- Entities carrying more than one active fact for the same predicate
SELECT subject, predicate, COUNT(*) AS cnt,
       GROUP_CONCAT(object, ' | ') AS conflicting_values
FROM kg_triples
WHERE valid_to IS NULL
GROUP BY subject, predicate
HAVING cnt > 1
ORDER BY cnt DESC;
```

For each contradiction: decide which fact holds (check against source material),
then `palace.py kg-invalidate` the wrong one. Some predicates legitimately hold
several values (certifications, languages) — those are not contradictions.

In `--auto` mode, do NOT invalidate anything without evidence. List the
contradictions under "Open questions" and let the next interactive run decide.
An unattended job that resolves ambiguity by guessing will eventually delete the
true fact and keep the false one.

## Phase 3.6 — Memory tier and retrieval health

```bash
python3 scripts/memory_tiers.py --report
```

If you keep an evaluation set of queries with expected results, run it here and
flag any drop in retrieval precision. Index health and retrieval health are
different things: an index can be perfectly in sync and still return the wrong
drawer for every real question.

## Phase 4 — Infrastructure check

```bash
ls .claude/skills/*/SKILL.md   # skills exist and are well-formed
ls -la .claude/hooks/*.sh      # hooks exist and are executable
ls .claude/agents/*.md         # agent definitions exist
```

```sql
SELECT MAX(occurred_at) AS last_twin_update
FROM activity_history WHERE action = 'twin_update_completed';
```

Flag the twin if it has not been updated in 7+ days.

## Dedup guard (MANDATORY before filing ANY proposal)

Whatever you use as a proposal backlog — the `tasks` table, an issue tracker, a
project board — check for an equivalent open item BEFORE filing a new one.

Without this guard the backlog fills with the same proposal filed once per run,
because each run rediscovers the same finding and has no memory that it already
reported it. A backlog nobody can read is the same as no backlog.

- Search with 2-3 **distinctive** keywords from the proposal (a script name, a
  table name, a skill name) — not generic words like "update" or "fix".
- **Match found** → do not file. If there is genuinely new evidence, add it to the
  existing item and reference it in the report as "already open as #N".
- **Equivalent item already rejected or closed** → do not reopen. Mention it only
  if the new evidence is materially different.
- **No match** → file it.

## Phase 5 — Propose improvements

From Phases 1-4, propose **1 to 3 concrete improvements**. Each must be:

- **Specific** — "add a hook that blocks writes to /tmp", not "improve security"
- **Actionable** — a clear next step: which file, which agent, what change
- **Justified** — the evidence from Phases 1-4 that prompted it

Categories: new skills for repetitive workflows, prompt adjustments for agents
that keep failing, schema changes for data you keep wishing you had, new hooks for
guardrail gaps, memory hygiene, process simplification.

Three is a cap, not a quota. "Nothing worth proposing this week" is a valid
outcome and a healthier one than three inventions.

**Present to the user. Never auto-implement.**

## Failure isolation

If any phase fails (a delegated agent errors, a network call is rate-limited), do
NOT abort the run. Record the failure in that section of the report and continue
to logging and output. A review that only completes when every phase succeeds
stops running exactly when the system is least healthy.

## Logging (MANDATORY)

```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, metadata, occurred_at)
VALUES (
  1,
  'kaizen_completed',
  'system',
  'Kaizen review: health score X/100, Y failures reviewed, Z improvements proposed',
  json_object(
    'health_score', ?,
    'failures', ?,
    'improvements_proposed', ?,
    'twin_days_stale', ?,
    'procedural_patterns', ?
  ),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
);
```

## Sentinel touch (MANDATORY at the end of a run)

In BOTH modes, as the very last step:

```bash
mkdir -p .kaizen && touch ".kaizen/$(date +%Y-%m-%d).done"
```

This makes the run idempotent: if the scheduler fires after a manual `/kaizen`,
the wrapper sees the sentinel and skips.

## Output format

```
## Kaizen Report — {date}

### System Health: XX/100
- [OK/WARN] Integrity
- [OK/WARN] Index sync
- [OK/WARN] Backlog: N pending
- [OK/WARN] Cost telemetry

### Failures (since last run)
- {count} failures, {patterns found}
- Most affected: {agent_name} ({N} failures)

### Procedural Memory
- {N} total patterns, {N} reliable, {N} never reused, {N} orphans

### Proposed Improvements
1. **{title}** — {description}. {justification}.

### Digital Twin
- Last updated: {date} ({N} days ago)

### Open questions
- {question} — assumed default: {default}
```

In `--auto` mode, write this report to a dated file rather than to the session,
and leave delivery (email, chat, wherever it needs to go) to the wrapper. The
skill's only job is to produce a correct report at a predictable path.
