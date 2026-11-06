# Changelog

What changed in the public template, newest first. Each entry is a sync from the
reference instance that has been running daily; only the generic part is carried over.

## 2026-11

Second sync from the reference instance. The common thread: behaviour that depended
on someone remembering became a hook with a test, and checks that could not fail were
replaced by checks that measure.

### Web access
- **Web access ladder** (`.claude/rules/web-access-escalation.md`): two automatic
  routes per site, then a block ladder (stealth read, optional paid routes, a real
  browser), then one request to the user. A captcha or a WAF means climb, not drop.
  A 200 response with a challenge page, an empty shell or a login wall counts as a
  failure.
- **Browser harness**: a real, dedicated Chrome with an empty profile, started on
  demand and stopped at the end. No agent logs into an account; when the user operates
  a site with their own account, the profile is cleared before the browser stops.
  The wrappers live in `scripts/bin/` and are configured through environment files.

### Hooks (each with a `.test.sh`; the whole battery runs with one loop)
- `secret-brake`: refuses a message shaped like a secret and points to the secrets
  channel. Never echoes what it caught.
- `copy-guard`: no copies of databases with personal data outside the destinations a
  retention routine sweeps. Inert until `copy-guard.conf` lists something.
- `correction-nudge`: from the second correction in the same session, a short reminder
  before the answer. Stores date, session and family only, never the text.
- `spec-criteria-gate`: ingests a spec's acceptance criteria at dispatch; a spec with no
  criteria is not dispatched.
- `agent-throttle`: warns, never blocks, when another agent is still running. The
  rate-based legs were removed: they warned on almost every dispatch and changed none.
- `prod-kill-guard`, `commit-nudge`, `automode-warn`.
- `session-stop-save` counts only messages the user typed; `sql-guardrails` checks
  both quoting forms and allows `wal_checkpoint(TRUNCATE)`.
- Smoke tests for the older hooks, so every hook in the folder has a test.

### Specs and the quality gate
- **Machine-readable spec criteria** (`scripts/spec_criteria.py`, migration 027): each
  `- [ ]` box is a row with a life cycle. The author claims with a pointer to the
  proof; someone else verifies; database triggers refuse an author verifying their own
  work. The spec template and the briefs README describe the contract.
- **Asymmetric quality gate**, extended: a `returned_to_author` outcome for every FAIL,
  a pass cap at the third pass that finds a new defect of the same family (the user
  chooses between shipping with a named protection or one more round with a deadline),
  and criterion-by-criterion checks for work that had a spec.

### Rules
- **Data boundary rules**: health data and company financial figures never go into
  shared memory (drawers, the database, the diary); memory gets a pointer to the file.
  Databases with personal data are read in place, never copied.
- Secrets channel, permissions scope.
- **Token discipline**: one brake (`maxTurns`); the handoff is written to disk before
  the first write that leaves the agent.

### Memory
- **Procedural memory**: the agent-outputs protocol now also asks for criteria claims
  and logs dispatch start and end, which the agent throttle reads.
- **Palace audit** (`scripts/palace_audit.py`): read-only, no model. Finds full-text
  index drift by a MATCH sweep, never by a row count, after proving on a throwaway
  database that it can detect the defect. Never prints drawer text or terms.
- Migration 025 fixes the full-text sync triggers (old words of a rewritten drawer
  stayed searchable). Migration 026 adds the stats view, and `palace.py` creates the
  vector table on first connection: a fresh install now passes `palace.py status`.
- `generate_memory_hot.py` runs on a fresh clone (missing import, placeholder paths).

### Protocols and docs
- Handoff on disk replaces the JSON checkpoint in the tasks table.
- Session end: one twin row per session end (completed or skipped), closing hygiene.
- `scripts/check_refs.sh`: every path, rule and wrapper the repo names must exist.
- `docs/install.md`: migrations 025 to 027 after the schema, and an end-to-end check.
- README: a "What it has built" section, with cases from the reference instance told
  by problem, agents, what the system does and where a person decides.

### Folders renamed (forks: action needed)
- `Team Inbox/` is now `inbox/` and `Owners Inbox/` is now `outbox/` (moved with `git mv`; subfolders unchanged; hooks, scripts, skills, rules, protocols, docs and schema comments follow). In a fork, run `git mv "Team Inbox" inbox && git mv "Owners Inbox" outbox` and update any path of your own that names the old folders.

### Rollback
The public state before this sync is commit `695a6c9`. To revert, use
`git revert <release commit>` and push. Never `push --force`: the Discussions live
on the public repository.
