# Team/_briefs — delegation specs

Working folder. This is where the orchestrator writes the **spec** before putting
the team to work. It is not a deliverable (those go to `outbox/`) and it is
not the user's input (that is `inbox/`).

## Rules

- **One spec per task**, filed as `YYYY-MM-DD-<slug>.md`, started from `_TEMPLATE.md`.
- **When a full spec is written:** substantial or multi-agent work (R4/R5). A
  single clear task (R3) gets a mini-brief inline in the dispatch, no file at all.
  Trivial work gets nothing.
- **Owner approval:** only for large or sensitive work (R5, class A/B/C, high
  risk). Otherwise the orchestrator writes the spec and proceeds.
- **The spec is the contract:** agents read it while working, and its acceptance
  criteria are the checklist the orchestrator verifies the deliverable against at
  the end. Those two being the same list is the whole point — a spec whose
  acceptance criteria are not literally checkable is a wish, not a contract.
- **The criteria have machine-readable state.** One criterion per `- [ ]` box,
  checkable by a file, a command or a row; the text is immutable after dispatch
  (a changed text is a new criterion, and the old one goes to `superseded`). The
  state lives in the `spec_criteria` table of `team.db` and changes **only**
  through `scripts/spec_criteria.py`: `claim` by the author with an evidence
  pointer, `verify`/`fail` by someone else, `waive` only with the owner's decision
  quoted. The boxes in the file are a derived view, ticked by `close`; ticking them
  by hand changes nothing. A spec dispatched without boxes under
  `## Acceptance criteria` is blocked at dispatch by
  `.claude/hooks/spec-criteria-gate.sh`; the way out is adding criteria to the file.
- **Mandatory external tools are tested before dispatch.** The `## Inputs / sources`
  line names each MCP server, API or paid service the task depends on, the date of
  the test and the minimal read call that returned OK. Without that test the
  dispatch does not go out: a connector that needs a paid plan, found out halfway
  through a run, costs far more than a read call of a few seconds.
- When the task closes, the spec can move to `_done/`. Do not delete it: it is the
  record of what the deliverable was verified against.

Context: the Digital Twin operating model in `CLAUDE.md` and `docs/architecture.md`.
