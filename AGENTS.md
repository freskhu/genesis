# AGENTS.md

> Conventions for extending Genesis with new agents and skills. Compatible with the [agents.md](https://agents.md) specification.

## What is an agent in Genesis

An agent is a specialised personality with a defined scope, invoked by the orchestrator via the `Task` tool. Agents have:

- **A name** (single first name, real-feeling).
- **A role** (one line — what they own).
- **A system prompt** in `.claude/agents/{name}.md` (front-matter + body).
- **A profile** in `Team/{name}.md` (longer narrative for the user).
- **A row** in `team_members` table.
- **A scope of tools** they may use.
- **A diary** — they record their work via `palace.py diary-write`.

## Creating a new agent

The supported path is the `/hire` skill:

```
/hire
```

It runs the pipeline: Maria researches the role, Sarah designs the agent, Lena registers it.

Manual creation is possible but discouraged — the pipeline ensures the agent is well-scoped and consistent with the rest of the team.

## Agent file structure

```markdown
---
name: lucia
description: Marketing Communications Specialist. Drafts newsletters, LinkedIn posts, and customer-facing copy in the user's voice.
tools: Read, Write, Edit, Glob, Grep, Bash
---

# Lucia — Marketing Communications

You are Lucia, the Marketing Communications Specialist for {{OWNER}}.

## Your style
[paragraph of voice, tone, register]

## What you own
- [responsibility 1]
- [responsibility 2]

## What you don't own
- [explicit boundaries]

## Standard outputs
- Drafts go to `Owners Inbox/Marketing/{date}-{title}.md`
- Final approval is always by the user.
```

## Skills (slash commands)

Skills live in `.claude/skills/{name}/SKILL.md` with front-matter:

```markdown
---
name: skill-name
description: One-sentence trigger explanation.
---

# Skill body — instructions Claude follows when invoked.
```

Use `/write-a-skill` to scaffold a new one.

## Hooks

Shell scripts in `.claude/hooks/` run on lifecycle events. Reference them in `.claude/settings.json`.

Examples:
- `sql-guardrails.sh` — blocks destructive SQL.
- `session-stop-save.sh` — auto-saves checkpoint to MemPalace before conversation ends.

## Memory conventions

Agents read and write MemPalace via `scripts/palace.py`. They MUST:

1. **Search before they write** — avoid duplicate drawers.
2. **Use semantic rooms** — never dump into generic `archive`.
3. **Always include `--hall`** — facts vs events vs preferences vs advice vs discoveries.
4. **Write a diary entry** at the end of significant work via `palace.py diary-write`.

## Database conventions

Agents do not write to the DB themselves. They request changes through Lena via the orchestrator. The orchestrator delegates the SQL to Lena, who runs it.

Required logs after every agent invocation:

- `llm_calls` row with token counts and cost.
- `activity_history` row describing the delegation.

## Voice conventions

The user's preferred language and tone are in `Team/orchestrator.md`. All agents inherit those defaults unless they have a specific override (e.g., a "deliver-bad-news" agent that's deliberately blunt).

## What NOT to do

- Don't create generic-named agents ("MarketingAgent", "CodeAgent"). Every agent has a real first name.
- Don't bypass the `/hire` pipeline for new agents.
- Don't write to memory or DB without going through `palace.py` / Lena.
- Don't share state between agents through global variables — agents are stateless. State lives in MemPalace and the DB.

---

For the wider architecture, see [`docs/architecture.md`](docs/architecture.md).
For writing new skills, see [`docs/writing-skills.md`](docs/writing-skills.md).
