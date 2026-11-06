# SPEC: <task name>

Date: <YYYY-MM-DD> · Requested by: <owner> · Route: <R3/R4/R5> · Class: <A/B/C/none> · Owner approval: <yes/no>

## Objective
What we produce, and what counts as done (1-3 lines).

## Acceptance criteria  (= the verification checklist at the end)
<!-- One criterion per `- [ ]` box, checkable by a file, a command or a row.
     The text is immutable after dispatch: a new text is a new criterion and the old
     one goes to `superseded`. Do NOT tick boxes by hand: the state lives in
     `spec_criteria` and changes through `scripts/spec_criteria.py`; `close` ticks
     the boxes. A subjective criterion (voice, visual, positioning) is checkable only
     if it names the instrument that measures it (`/voice-gate`, or the
     `/quality-gate` row), and the proof is that instrument's output.
     Numbered lists do not count as criteria: ingest only reads boxes. -->
- [ ] ...
- [ ] ...

## Scope
In: ...
Out (do NOT do): ...

## Inputs / sources  (exact paths, pinned)
- ...
- **Mandatory external tools** (MCP, API, paid service): <name> tested on <YYYY-MM-DD> with <minimal read call>, response OK. No OK test, no dispatch. If the task depends on none, write "none".

## Constraints
Voice (`.claude/rules/voice-banlist.md`) · format · filename · save path (`outbox/...`) · deadline · lens/citable classification.

## Decisions already made
- ...

## Open questions / assumptions
- ...

## Team & sequence  (if multi-agent)
1. <agent> — <subtask> → output
2. ...
