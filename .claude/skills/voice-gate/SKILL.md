---
name: voice-gate
description: Hard-block voice gate. Reads a target file, runs the Tier 1 banlist check against `.claude/rules/voice-banlist.md`, returns a passed/blocked verdict. Use as a pre-flight gate for anything published in someone else's voice, before the quality-gate review pass.
user-invocable: true
argument-hint: "[path to the file to check]"
allowed-tools: Read Bash Glob
---

# Voice Gate — hard-block pre-flight

Validates a deliverable against `.claude/rules/voice-banlist.md` and returns a
structured verdict.

**Prerequisite:** a banlist at `.claude/rules/voice-banlist.md`. The repo ships
`voice-banlist.example.md` — European Portuguese, plus the language-neutral AI
tells. Copy it, cut what does not apply to you, and add what your own writing
keeps getting wrong. A banlist copied wholesale from someone else's voice blocks
sentences you would have wanted and lets through the ones you would not.

## When to invoke

Anything a third party will read in someone else's voice:

- Owner-voice external commercial writing (client and supplier email, quotations)
- Co-authored or academic prose that the user will sign
- Branded, published content (posts, deck copy, visual copy)

**Rule of thumb:** if in doubt, invoke. The asymmetry is one turn of overhead
against a voice violation that ships and cannot be recalled.

## Usage

```
/voice-gate <path>
```

## Behaviour

1. Resolves the path (absolute, or relative to the project root).
2. Runs `.claude/skills/voice-gate/check.sh` against the file.
3. Returns:
   - **`VERDICT=passed`** → exit 0. Safe to hand on.
   - **`VERDICT=blocked`** → exit 1, with violations by category. Refine and re-invoke.
   - **`VERDICT=error`** → exit 2. File missing or unreadable.

Context is read from `voice-context:` front matter when present, otherwise
inferred from the path. Files in a `documentation` context exit clean: docs that
catalogue these patterns would otherwise flag every example they teach.

## Composition with `quality-gate`

Voice-gate runs **before** the quality-gate review pass. This ordering is
deliberate:

- Voice-gate catches deterministic Tier 1 violations cheaply and mechanically.
- The reviewer then spends their attention on substantive critique — voice fit,
  structure, factual integrity — instead of on textbook AI tells a regex could
  have caught.

Order for a gated deliverable:

1. Agent produces the draft
2. `/voice-gate <file>` → must pass
3. `/quality-gate <file>` → review pass (mandatory for A/B/C class; see
   `.claude/protocols/quality-gate.md`)
4. Delivery

## Out of scope

Voice-gate does not replace human review for nuance — tone fit, persona, register.
It blocks only unambiguous Tier 1 violations. The judgement about whether
something *sounds right* still belongs to a reader.
