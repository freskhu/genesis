# Writing skills

A *skill* in Genesis is a reusable workflow — invoked with a slash command in Claude Code (`/dream`, `/hire`, `/kaizen`, etc.). Skills live in `.claude/skills/{name}/SKILL.md`.

The fastest way: run `/write-a-skill` and follow the scaffold. The notes below explain what's actually going on.

## Anatomy

```markdown
---
name: skill-name
description: One-sentence description that helps the model decide when to use it.
---

# Skill name — short purpose

[Short overview — 1-2 sentences.]

## When to invoke
[Triggers, contexts, who calls it.]

## Steps
1. [explicit step 1]
2. [explicit step 2]
3. ...

## Outputs
[What the skill produces — files, DB rows, MemPalace entries.]

## Anti-patterns
[Common mistakes to avoid.]
```

The front-matter is what Claude reads to decide when this skill applies. **Keep `description` action-triggered**: "Run weekly review and 1-week health check" beats "weekly review skill."

## Length

A skill file should be **under 100 lines** in 90% of cases. If you need more:

- Split into separate reference files (`HOW-TO-X.md`) and link from the main `SKILL.md`.
- Move long examples or templates to a `_examples/` subfolder.

The `SKILL.md` is what Claude reads in full every time. Bloat = noise.

## Steps that interact with state

Most skills touch one or more of:

- **MemPalace:** `python3 scripts/palace.py {add|search|kg-add|...}`
- **Operational DB:** `sqlite3 Database/team.db "SQL"`
- **Filesystem:** read from `Team Inbox/`, write to `Owners Inbox/`

Be explicit about which side-effects happen. If your skill writes to MemPalace, say which `--wing`, `--room`, `--hall` get the entry.

## Invoking other skills

Skills can invoke other skills:

```
At the end of /weekly-review, suggest /quarterly-review if 3 months elapsed.
```

But the orchestrator is the one that actually invokes skills. Skill files describe behaviour; they don't execute.

## Skills vs hooks

| Skills | Hooks |
|---|---|
| User-invoked (slash command) | System-invoked (lifecycle event) |
| Live in `.claude/skills/` | Live in `.claude/hooks/` |
| Markdown instructions for Claude | Shell/python scripts that the harness runs |

If something must run automatically (e.g., before every commit, after every session), it's a **hook**, not a skill.

## Examples to study

- `/genesis` — long, conversational, with branching. Uses `AskUserQuestion`. Generates files and DB rows during the flow.
- `/dream` — short, programmatic. Calls a Python script.
- `/hire` — orchestration of multiple agents (Maria → Sarah → Lena).
- `/kaizen` — periodic review with structured output.

Read those files in `.claude/skills/`. Imitate the shape.

## When NOT to write a skill

- For one-off tasks. Skills are meant to be reused.
- For things that fit naturally in an agent's prompt. If only one agent ever does this, put it in their system prompt.
- For shell automation that doesn't need Claude. That's a `Makefile` / shell script, not a skill.
