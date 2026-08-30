# Quality Gate Protocol — Voice/Brand Second-Pass

**Owner:** your QA reviewer agent (create one if you have none — a reviewer that
did not write the draft is the whole point).
**Trigger:** before the orchestrator delivers an A/B/C-class artifact to the user
(see scope). Distinct from the user-invoked `/quality-gate` skill — this is the
orchestrator's automatic, classification-driven routing rule.

## What this is

An **asymmetric** gate. The cost of voice or brand drift in owner-voice,
co-authored, and published material is high and hard to reverse once it has left
the building. The cost of an extra QA pass on internal code and internal reports
is delivery friction with little upside. So the gate is mandatory only where drift
is expensive, and optional everywhere else.

The asymmetry is the design. A blanket "review everything before delivery" rule
reads as rigour and behaves as a tax: it slows every delivery equally, so people
start routing around it, and it stops protecting the cases that actually needed it.

## Mandatory scope — exactly three classes

The mandatory second pass fires ONLY for these:

- **Class A — Owner-voice / external commercial.** Anything sent to a client,
  supplier or counterparty over the owner's name: emails, negotiation replies,
  quotations that leave the building.
- **Class B — Co-authored / academic prose.** Work the user will submit or sign
  as their own writing.
- **Class C — Branded / published.** Visuals, decks, social posts — anything that
  carries the brand in public.

Anything outside A/B/C is **NOT** mandatory-gated: code, agent definitions,
backtests, DB migrations, internal research, internal reports. For those the
orchestrator adds a single OPTIONAL line to the cover note:

> Want a QA pass on this before it goes out?

If the user declines or does not answer, delivery proceeds. Do not block non-A/B/C
work.

## Non-negotiables

1. **Read the original briefing.** The critique pass MUST read the original
   briefing or request, not only the draft. Content the user explicitly asked to
   include verbatim must NOT be flagged as invented. A reviewer that flags the
   user's own words as a hallucination burns trust faster than the defects it
   catches, and after two of those nobody reads the gate output again.
2. **The gate never silently rewrites a deliverable.** It produces findings and a
   structured outcome; the author or the orchestrator decides what changes.
3. **A deliverable that genuinely passes is recorded as `passed_unchanged`.** Do
   not invent findings to justify the pass. A reviewer with a quota finds things
   that are not there.

## Triage depth (WITHIN the A/B/C gate only)

This table sets review depth once an item is already in scope. It is NOT a
universal trigger.

| Level | Within-scope criteria | Review depth |
|-------|----------------------|--------------|
| **Critical** | Externally-binding commercial text (quotations, negotiation commitments), final submitted work | Full review: every claim, every figure, every voice cue |
| **High** | Owner-voice client/supplier emails, co-authored prose, published branded content | Checklist review: systematic pass through all criteria |
| **Medium** | Lower-stakes branded content (internal-facing decks, draft visuals) | Spot-check: voice/brand cues plus factual anchors |
| **Low** | Minor edits to an already-gated, already-passed artifact | Confirm the delta only |

## Review criteria (A/B/C)

1. **Voice fidelity** — does it sound like the owner, the co-author, the brand? No
   generic corporate language, no thought-leader speak, no invented metaphor the
   user could not defend in thirty seconds if asked where it came from.
2. **Source & briefing fidelity** — every claim traceable to a source or to the
   original briefing. Verbatim-requested content is honoured, not flagged.
3. **Grounding** — anchored in the real context (the user's actual profile, the
   actual company, the actual project). No drift into generic positioning.
4. **Logical coherence** — the argument flows; conclusions follow from the
   evidence presented.
5. **Completeness** — no gaps the briefing required, no unanswered question the
   deliverable itself promised to answer.

## Structured outcome (MANDATORY)

Every gate run produces TWO fields, because "is it defective" and "did anything
change" are different questions and collapsing them hides the gate's real value:

- **Verdict** (is it defective): `PASS` / `PASS WITH NOTES` / `FAIL`
- **Outcome** (did the deliverable change): exactly one of
  - `passed_unchanged` — nothing material found; ships as-is
  - `materially_refined` — findings led to substantive changes before delivery
  - `surfaced_for_decision` — flagged something needing the user's or author's
    judgement; not auto-resolved
  - `deliberately_overridden` — findings raised, and the author consciously chose
    to ship anyway, with a rationale

Without the outcome field, a gate that passes everything unchanged and a gate that
rewrites half of what it sees look identical in the logs, and you cannot tell
whether it is earning its cost.

Both fields go to `activity_history`:

```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, metadata)
VALUES (
  (SELECT id FROM team_members WHERE name = '{reviewer}'),
  'quality_gate',
  'deliverable',
  'Quality Gate [{class}/{triage}] {item}: {verdict} / {outcome}',
  json_object(
    'item',              '{deliverable_name}',
    'class',             '{A|B|C}',
    'triage_level',      '{Critical|High|Medium|Low}',
    'verdict',           '{PASS|PASS WITH NOTES|FAIL}',
    'outcome',           '{passed_unchanged|materially_refined|surfaced_for_decision|deliberately_overridden}',
    'briefing_read',     '{yes|na_reason}',
    'findings_count',    '{n}',
    'outcome_rationale', '{one_line}',
    'reviewed_at',       strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
  )
);
```

## Report format

```
## Quality Gate: [Item Name]
**Class:** A / B / C
**Triage Level:** Critical / High / Medium / Low
**Verdict:** PASS / PASS WITH NOTES / FAIL
**Outcome:** passed_unchanged / materially_refined / surfaced_for_decision / deliberately_overridden
**Review Date:** YYYY-MM-DD
**Briefing read:** Yes — [source/path] / N/A with reason

### Findings
#### [Finding Title]
- **Severity:** Critical / High / Medium / Low
- **What:** [defect]
- **Why it matters:** [impact — voice, brand, trust cost]
- **Suggested fix:** [resolution]

### Outcome Rationale
[One line: why this outcome state, especially for surfaced_for_decision or deliberately_overridden]
```

## Who does what

- **The orchestrator:** classifies the deliverable at delivery time (A/B/C →
  mandatory; anything else → the optional cover-note offer); routes A/B/C to the
  reviewer BEFORE writing the cover note; never presents a FAILed artifact to the
  user as a deliverable — it goes back to the author and is reported as a status.
- **The reviewer:** reads the original briefing first, runs the triage and the
  review criteria, emits Verdict plus Outcome, and logs the `activity_history`
  row. The gate is not closed until that row exists.

## Related

- `.claude/skills/quality-gate/` — the user-invoked version of this checklist.
- `.claude/skills/voice-gate/` — a hard block on Tier 1 voice violations. Run it
  BEFORE this gate for A/B/C items: mechanical checks are cheap and should not
  consume a reviewer's attention.
- `.claude/rules/` — the voice banlist the voice gate reads.
