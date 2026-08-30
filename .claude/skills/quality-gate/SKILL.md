---
name: quality-gate
description: "Pre-delivery review of a deliverable: structural blockers first, then substance. Use before anything leaves the building — external email, published content, submitted work."
user-invocable: true
argument-hint: "[path to the file to review]"
allowed-tools: Read Bash Grep Glob
---

# Quality Gate — pre-delivery review

The user-invoked counterpart to `.claude/protocols/quality-gate.md`. The protocol
decides *what gets gated*; this skill is *how one item is reviewed*.

Two tiers. Structural items are **blocking** — they are mechanical, cheap, and
have no judgement in them. Substance items are **warnings** — they need a reader,
and they are where the review actually earns its cost.

Run the structural pass first. A reviewer who spends their attention on a missing
caption has none left for the argument.

## Inputs

- **File path** — passed as an argument, or asked for if missing.
- **The original briefing** — MANDATORY. Read it before the draft. Content the
  requester asked for verbatim must not be reported as invented, and a reviewer
  who flags the requester's own words loses the requester's trust permanently.
- **Your voice rules**, if you keep any: `.claude/rules/voice-banlist.md`.

## Step 0 — Set the bar

Not every deliverable needs the same score. Establish the type first, then the
minimum, then review against it:

| Deliverable | Blocking items that must pass |
|---|---|
| Internal memo / working note | Structural items only, loosely |
| Report for a named audience | All structural, no open warnings on substance |
| Anything sent to a third party | All structural, all substance |
| Anything published under a brand | All structural, all substance, plus a voice pass |
| Draft explicitly marked as a draft | The gate does not apply |

A single universal bar means either everything is over-reviewed or the bar is set
where the cheapest item can clear it.

## Step 1 — Structural pass (BLOCKING)

Run each check and report PASS/FAIL **with the evidence**. "Item 4 failed" is not
a finding; "line 82 repeats line 81 verbatim" is.

1. **Naming** — a predictable, sortable filename: date, subject, descriptor.
2. **Metadata** — title, author, date present in whatever the format supports
   (YAML front matter, document properties, a title slide).
3. **No adjacent duplicate paragraphs** — the classic generation artefact:
   ```bash
   awk 'NR>1 && length($0)>10 && $0==prev {print NR": "$0} {prev=$0}' <FILE>
   ```
4. **Figure flow** — every image has its own caption; no bare image immediately
   after a heading; the rhythm is heading → text → figure → text.
5. **Convention consistency** — callouts, symbols and colours applied uniformly,
   or uniformly absent. Half-applied is worse than absent.
6. **Language consistency** — one language throughout, correct diacritics, one
   font. A document that drops its accent marks halfway through was written in
   two sittings and reads like it.
7. **Cross-references resolve** — internal links land, every citation has an
   entry, figure and table numbers are right, external URLs spot-checked.
8. **Tables and structure** — equal column counts per row, consistent list
   indentation, code blocks with a declared language, nothing cut off at a margin.
9. **No generation markers** — the sycophantic openers, the hedging phrases, the
   throat-clearing transitions. If you keep a banlist, run `/voice-gate <file>`
   here instead of grepping by hand, and let this item inherit its verdict.

## Step 2 — Substance pass (WARNINGS)

10. **Density** — long sentences carrying little information, repetition,
    adjectives standing in for facts. Or the reverse: a wall with no headings.
11. **Actionability** — does it answer "so what happens now?" An analysis needs
    recommendations with an owner. A memo needs the decision it is asking for. A
    manual needs steps someone can actually follow.
12. **Fidelity** — every claim traceable to a source or to the briefing; the
    framing matches the real context rather than a generic version of it; nothing
    invented to fill a gap the author could have left open.

## Step 3 — Score and verdict

```
=== QUALITY GATE — <filename> ===
Type: <type>

[1] Naming          PASS/FAIL
[2] Metadata        PASS/FAIL
[3] No duplicates   PASS/FAIL
[4] Figure flow     PASS/FAIL
[5] Conventions     PASS/FAIL
[6] Language        PASS/FAIL
[7] Cross-refs      PASS/FAIL
[8] Tables/struct   PASS/FAIL
[9] Voice markers   PASS/FAIL
---
[10] Density        PASS/FAIL (warning)
[11] Actionability  PASS/FAIL (warning)
[12] Fidelity       PASS/FAIL (warning)

BLOCKERS: <failed structural items, or "none">
WARNINGS: <failed substance items>

VERDICT:
  DELIVER              — clears the bar for this type
  DELIVER WITH NOTES   — clears the bar, N warnings worth addressing
  DO NOT DELIVER       — N blocker(s), fix and re-run

NEXT ACTIONS:
  1. <specific fix, with the line it applies to>
```

## Step 4 — Evidence for every FAIL

For each failure: the exact line or section, what is wrong with it, and the
suggested replacement. A verdict without evidence is an opinion, and the author is
entitled to disagree with it.

## Step 5 — Log the outcome

```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, metadata, occurred_at)
VALUES (1, 'quality_gate_run', 'document',
  'QG <filename>: <verdict>',
  json_object('file','<path>','blockers',<n>,'warnings',<n>,'verdict','<verdict>'),
  strftime('%Y-%m-%dT%H:%M:%SZ','now'));
```

## Notes

- This skill diagnoses; it does not auto-fix. The author decides what to change.
- If the same item fails repeatedly across deliverables, the convention may be the
  problem rather than the author. Say so.
- Compose with `/voice-gate`: run that first for A/B/C-class work, so the
  mechanical voice violations are gone before a reviewer's attention is spent.
