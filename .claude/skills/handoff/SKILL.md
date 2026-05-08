---
name: handoff
description: "Package shaped context -- plans, decisions, project state -- into a structured handoff document for another AI agent, your future self, or a coworker. Use when user mentions 'handoff', needs to transfer context between sessions, or wants to package project state for someone else."
---

# Handoff

Package shaped context into a structured document for handoff to another agent, future self, or coworker.

## Input

**Mode:** Parse first argument:
- **"list"** -- Show all existing handoffs
- **"update [slug]"** -- Append to existing handoff
- **"view [slug]"** -- Read and summarize existing handoff
- **Anything else / empty** -- Create new handoff

## Before Starting (Auto-Gather)

Silently gather context:
1. **MemPalace** -- `python3 scripts/palace.py search "active projects current state" --limit 5`
2. **Task state** -- `SELECT id, title, status, description FROM tasks WHERE status IN ('in_progress', 'pending') ORDER BY updated_at DESC LIMIT 10;`
3. **Git state** (if in a repo) -- `git log --oneline -20`, `git status`, `git diff --stat`
4. **Directory structure** -- `ls` at repo root

Do NOT display what you gathered. Hold as context.

## Mode: Create (Default)

### Step 1: Determine context source

Check for active tasks, plans, or project state. If found, use as basis. If not, ask the user to describe the project state.

### Step 2: Ask focused questions

1. **"Who is this handoff for?"** -- AI agent, myself later, or a coworker
2. **"Anything to add beyond what's in the context?"** -- gotchas, failed approaches, constraints

### Step 3: Generate the handoff

Use the appropriate template based on audience. Save to MemPalace and optionally to a file.

See [examples/](examples/) for complete handoff examples.

## Templates

### AI Agent Template

Optimize for an agent to pick up and work immediately with zero additional context.

Sections: Summary, Project Context, The Plan, Key Files (table), Current State (Done/In Progress/Not Started), Decisions Made (with reasoning), Important Context (gotchas), Next Steps (priority-ordered with acceptance criteria), Constraints.

### Self/Later Template

Optimize for fast context recovery -- "where was I and what was I thinking?"

Sections: Where I Left Off, The Plan, What's Working, What's Not Working Yet, My Current Thinking, Decisions I've Made, Things I Tried That Didn't Work, Next Time I Pick This Up, Open Questions.

### Coworker Template

Optimize for readability -- assume no context on this work.

Sections: TL;DR, Background, The Plan, What's Done, What's Left, Key Decisions, Things to Watch Out For, Where to Get Help.

## Storage

Save handoffs to MemPalace for retrieval across sessions:
```bash
python3 scripts/palace.py add --wing ai_team --room protocols --hall hall_advice --content "[handoff content]"
```

Also update task checkpoints in team.db for operational continuity:
```sql
UPDATE tasks SET description = json_object('handoff', '[summary]', 'checkpoint_at', strftime('%Y-%m-%dT%H:%M:%SZ', 'now')) WHERE id = {task_id};
```

## Mode: List / Update / View

- **List**: Query MemPalace for handoff entries, display as table
- **Update**: Find existing handoff, append new context section
- **View**: Read full handoff, present conversational summary
