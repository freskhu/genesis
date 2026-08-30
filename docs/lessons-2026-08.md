# Lessons from the first audit

After a few months of daily use, the reference instance of this template was
audited end to end — memory, agents, hooks, protocols, scheduled jobs, cost,
security. Seven findings generalise beyond that one instance. They are here
because each of them was cheap to design in on day one and expensive to retrofit.

The instance-specific numbers are deliberately absent. What survives is the shape
of each mistake.

---

## 1. Hooks beat rules. Native events beat hooks.

Two related findings, in that order.

**What has a hook happens. What only has a written rule happens sometimes.** The
audit measured this directly: protocols backed by a hook showed up in the activity
log hundreds of times; protocols that existed only as a written instruction showed
up zero times, all-time, despite being marked MANDATORY in bold. Not "less often" —
zero. The rule was correct, agreed, and documented, and it simply never fired.

So: if a behaviour must happen every time an event happens, it belongs in a hook.
A rule in an instructions file is a hope. This is why the `board-sync-reminder.sh`
hook in this template exists at all — the rule it enforces was already written down
and the board still drifted.

**But check what the runtime already does before you write the hook.** Several
hand-rolled hooks in the audited instance were reimplementing behaviour the harness
had since shipped natively. A `PostToolUse: Task` hook approximating a real
`SubagentStop` event. Two hooks on `Stop` doing session-end work, when `Stop` fires
per turn and a real `SessionEnd` exists. A whole manual ritual for recovering
truncated subagents, obsoleted by a resume mechanism that preserves the full
history.

The instance was using four hook events out of the thirty the runtime documents.
The pattern is not "we wrote bad hooks" — the hooks were good when written. It is
that a hand-built mechanism has no upgrade path: nothing tells you the platform
grew a native version. Re-read the events list when you upgrade, and delete what
the platform now does for you.

The hooks in this template are written against the events that exist today. Check
them against your runtime version rather than assuming.

## 2. Back up the database on day one

The single finding with irreversible loss, and three independent reviewers reached
it separately: no automatic backup of the operational database. None. The most
recent copies were months old, sat inside a synced cloud folder — so a synced
deletion removes them everywhere at once — and the database itself had been moved
out of that folder for an unrelated reason, leaving it with no off-machine copy at
all.

Everything else in an audit is a matter of degree. This one is binary.

Two rules:

- **Never back up a live SQLite database with `cp`.** In WAL mode the file on disk
  is not the database — the recent writes are in the `-wal` sidecar. Copying the
  main file alone yields a torn snapshot that restores as a database from an
  arbitrary point in the past, silently. Use `VACUUM INTO '/path/backup.db'`, which
  is transactional and produces a consistent standalone file, or a streaming
  replicator such as Litestream for continuous backup.
- **A backup you have never restored is not a backup.** Schedule an actual restore
  into a scratch path and run one query against it. Retention with no tested
  restore is a folder of files you hope are useful.

## 3. `maxTurns` is a per-tier setting, not a default

In the audited instance, 26 of 30 agent definitions carried the same `maxTurns`
value, with no relationship to the work each does. A five-minute lookup and a
multi-file build had the same budget.

The consequence was visible in the procedural memory: two of the five most-used
learned patterns were about *recovering a truncated subagent*. The system had
learned, at real cost, to recover from a failure it could have avoided by setting
one number correctly. That is what a wrong default looks like from the inside —
not an error message, but institutional knowledge accumulating around a workaround.

Set the cap by tier of work: a lookup agent, a writing agent, and a build agent
need different numbers. When an agent stalls between phases, read its frontmatter
before assuming a bug.

## 4. Memory layers need a contract, not just coexistence

The audited instance ran three memory layers at once: the harness's own always-on
memory index, a generated session briefing, and the hot tier of the knowledge
store. Each was individually well built. Together they had no precedence rule and
partly overlapping content, and the combined always-loaded context had grown to a
size nobody had chosen — it was the sum of three separate reasonable decisions.

Before adding a second memory layer, write down:

- **What goes in each**, in one sentence, such that a new fact has exactly one home.
- **Which wins on conflict.** Two layers disagreeing about the same fact with no
  precedence rule means the agent believes whichever it read last.
- **A budget for the always-loaded portion**, and a way to measure it. Anything
  loaded on every session is paid for on every session, so it is the one number
  worth watching. Everything else can be retrieved on demand and costs nothing
  until it is used.

Related: the audit found three different counts of the same quantity circulating in
three documents. That is a documentation defect, not a data defect, and it is the
argument for never writing a count into a document that a query can answer. This
template's own instruction is "do not trust numbers written in docs" — worth
applying to the docs themselves.

## 5. Identifiers that encode the wrong measure

Cost telemetry in the audited instance was split across forty distinct agent-name
strings for thirty agents. The largest consumers were invisible because their spend
was divided across three spellings of the same name. Every aggregate query was
correct and every answer was wrong.

The general shape: a free-text column used as a grouping key will drift, and the
drift is invisible precisely because each individual row looks fine. If you group
by it, constrain it — a foreign key to the roster, or at minimum a CHECK against a
known set. Migration 023 in this repo is the same lesson applied to a different
column.

A related version: a cost column defaulted to zero when the token counts were
unknown. A zero is indistinguishable from a genuinely free call, so the gap never
surfaced and spend was under-reported by construction. NULL is the honest value for
"unknown", because NULL is visible in an audit and zero is not. That is why the
migration in this repo computes cost in a trigger and leaves NULL when it cannot.

## 6. A probe with no reach is not evidence of absence

Two findings in the audit turned on this, one in each direction.

A reviewer measured a database setting, found it disabled, and concluded the
production system ran without referential integrity. It did not: the setting is
per-connection and defaults off in the CLI the reviewer used. The application code
enables it on every connection. The measurement was accurate and the conclusion was
false, because the probe was not connected to the thing being described.

Separately, an agent lost filesystem access mid-task and reported findings as
absent that it simply could not see.

The discipline: before reporting "X is absent", run a positive control — a probe
that is *known* to produce a hit — through the exact same path. If the control does
not come back, the tool is broken, not the system. An audit that cannot distinguish
"not there" from "cannot see" produces confident, wrong findings, and those cost
more than no findings at all.

## 7. A classifier wired to an actuator needs a way to refuse

The audited instance ran an automated quality check with a physical consequence: it
inspected engineering drawings and stamped them. Its verdicts were binary. It had
no third state.

Two things follow from having only "pass" and "fail":

- **It must decide even when it cannot.** Every input gets a verdict, including the
  ones outside what the checker can actually judge. There is no way to express
  "this is beyond me" and stop, so low-confidence cases are indistinguishable in
  the output from confident ones.
- **Its own failures are invisible.** In this instance the checker wrote its results
  to a database path that did not exist, so failed runs left no trace and the
  weekly health report counted a fraction of the real failures. An actuator whose
  instrumentation is broken is worse than one with none, because it reports success.

If a classifier's verdict triggers an action in the world, give it three outcomes —
pass, fail, and *cannot judge, escalating* — and verify its logging path with a
positive control before you trust the counts. This is the same principle as the
asymmetric quality gate in `.claude/protocols/quality-gate.md`: a reviewer that must
always produce a verdict will produce one whether or not it has grounds.

The same logic applies to the permission layer. An allowlist with hundreds of
entries and not one `deny` or `ask` rule is a log of approved commands, not a
control — a classifier that can only ever say yes.

---

## The one-line version

Put the rule where it cannot be skipped, back the data up before anything else,
and make sure your instruments can see what you are asking them about.
