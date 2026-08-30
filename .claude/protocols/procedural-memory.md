# Procedural Memory (Institutional Learning)

**Trigger:** Before delegating (query existing patterns) AND after successful non-trivial delegation (record new pattern).

The `procedural_memory` table stores successful patterns that agents discover. This creates institutional learning — what worked once gets reused.

## When to RECORD a procedure (after successful agent completion)

After an agent completes a task successfully, the orchestrator MUST check whether the approach was non-obvious or reusable. If it was, record it with `palace.py proc-record`:

```bash
python3 scripts/palace.py proc-record \
  --trigger "{what_triggers_this_pattern}" \
  --action  "{what_to_do}" \
  --name    "{short_name}" \
  --steps   "step1 -> step2 -> step3" \
  --context "{what_context_is_needed}" \
  --tags    "comma,separated,tags" \
  --agent   "{agent_name}" \
  --outcome success
```

`proc-record` is an upsert: first sighting of a trigger inserts the row, every
later call with the same trigger increments the counter instead of creating a
twin. It also fills `dedup_key`, which is what makes that matching possible.

**Do not hand-write the INSERT.** A row inserted by hand has `dedup_key` NULL, and
in SQL NULL equals nothing — so `proc-record` can never find that row again. It
falls through to its insert branch and creates a duplicate at `success_count = 1`
while the original sits there, permanently unreachable. Rows in that state are
invisible to the loop that is supposed to promote them.

## When to QUERY procedures (before delegating)

Before delegating a task (R3/R4/R5), the orchestrator MUST check for matching procedures:

```sql
SELECT id, name, trigger_pattern, action, steps, success_count, failure_count, success_rate, source_agent
FROM procedural_memory
WHERE trigger_pattern LIKE '%keyword%' OR tags LIKE '%keyword%'
ORDER BY success_rate DESC, success_count DESC
LIMIT 3;
```

Select `id` and `trigger_pattern` deliberately: whoever applies the pattern needs a
key to increment it with afterwards. A query that returns only the steps produces an
agent that follows the pattern and then cannot record that it did.

If a matching procedure exists with `success_rate > 0.7`, include it in the agent prompt:
> "PROVEN PROCEDURE (success_rate: {rate}): {steps}. Follow this approach unless you have a strong reason to deviate."

## When to UPDATE counters (MANDATORY — this closes the institutional-learning loop)

**Whenever you reuse an existing procedure — you queried `procedural_memory`, found
a match, and applied it — you MUST increment its counter BEFORE closing the task.**
This is the single most important rule in this protocol. Without the increment,
every pattern looks single-use forever and the "reliable" bar can never be reached.

### Path A (preferred) — increment by `id`, one line of SQL

You applied a pattern that came out of the query above? Run this **immediately**,
with the `id` you noted. It costs milliseconds and does not require reproducing the
`trigger_pattern` exactly:

```bash
# success — the pattern worked
sqlite3 Database/team.db "UPDATE procedural_memory SET success_count = success_count + 1, last_used_at = strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id = {ID};"

# failure — you followed the pattern and it did not work
sqlite3 Database/team.db "UPDATE procedural_memory SET failure_count = failure_count + 1, last_used_at = strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id = {ID};"
```

Notes on the columns:

- They are `success_count`, `failure_count`, `last_used_at`, `id`. There is no
  `used_count` and no `updated_at`.
- `success_rate` is a GENERATED STORED column. **Never write to it** — SQLite
  recomputes it on the UPDATE, and assigning to it raises an error.
- Use `strftime('%Y-%m-%dT%H:%M:%SZ','now')`, the same format `proc-record` writes.
  `datetime('now')` produces a space instead of the `T` and mixes two styles in one
  column, which then breaks every range query someone writes against it later.

### Path B — increment by `--trigger`

The alternative when you have the trigger to hand but not the `id`. Works only on
rows whose `dedup_key` is populated:

```bash
python3 scripts/palace.py proc-record --trigger "{matched_pattern_trigger}" --outcome success
python3 scripts/palace.py proc-record --trigger "{matched_pattern_trigger}" --outcome failure
```

If the pattern you applied has `dedup_key` NULL, use Path A. Check with:

```sql
SELECT id, dedup_key FROM procedural_memory WHERE id = {ID};
```

### Exactly when to increment

At the close of the delegation, in the same block where you log the `llm_calls` row
and the diary entry. Do not leave it for the end of the session: by then the `id`
is gone from working context and the increment silently does not happen.

## Kaizen reviews procedures

During `/kaizen`, check for procedures with low success rates:
```sql
SELECT name, success_rate, success_count + failure_count AS total_uses
FROM procedural_memory
WHERE success_rate < 0.5 AND (success_count + failure_count) >= 3;
```
Flag these to the user for review or deletion.

Also check the health of the increment loop itself — orphan rows `proc-record` can
never reach:

```sql
SELECT COUNT(*) AS orphans_without_dedup_key FROM procedural_memory WHERE dedup_key IS NULL;
```

If that number rises between kaizen runs, someone went back to hand-written INSERTs.

Patterns that have earned the "reliable" bar:

```sql
SELECT name, action, success_rate, success_count
FROM procedural_memory
WHERE success_rate >= 0.8 AND success_count >= 3
ORDER BY success_rate DESC, success_count DESC;
```

The threshold sits at `success_count >= 3` rather than 5 deliberately: the bar has to
stay reachable while the increment discipline is still taking hold, or the whole
table reads as "nothing is proven yet" and agents stop consulting it.
