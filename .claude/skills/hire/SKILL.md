---
name: hire
description: "Full hiring pipeline: identify skill gap -> Maria researches -> Sarah hires -> Lena syncs DB"
user-invocable: true
argument-hint: "[role description or task that needs a specialist]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Agent"]
---

# Hiring Pipeline

## Step 1 -- Identify the Gap

The orchestrator determines that no existing team member can handle the task. Check the roster:
```sql
SELECT id, name, role, status FROM team_members WHERE status = 'active';
```

If no match, proceed with hiring.

## Step 2 -- Maria Researches

Delegate to Maria (Senior Researcher):
- "Maria, pesquisa o que um expert real em [AREA] sabe, faz, e prioriza."
- Maria uses WebSearch and WebFetch to research real-world professionals
- Maria delivers a research brief to `Owners Inbox/Team Reports/research-brief-[role].md`

## Step 3 -- Sarah Hires

Delegate to Sarah (HR Manager) with Maria's research brief:
- Sarah designs the new team member: name, persona, identity, skills
- Sarah creates:
  1. Agent definition in `.claude/agents/<name>.md`
  2. Profile in `Team/<name>.md`
  3. Updates `Team/roster.md`

## Step 4 -- Lena Syncs DB

MANDATORY -- hire is NOT complete until DB is updated.

Delegate to Lena:
```sql
INSERT INTO team_members (name, role, status, profile_path, agent_path, joined_at)
VALUES (?, ?, 'active', 'Team/<name>.md', '.claude/agents/<name>.md', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
```

Log the hire:
```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary, occurred_at)
VALUES (1, 'hire_completed', 'team_members', 'Hired [name] as [role]', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
```

## Step 5 -- Delegate Original Task

Now delegate the original task to the new hire.

## Rules

- Never skip steps. Always Maria -> Sarah -> Lena.
- Every hire must have: agent definition, profile, roster entry, DB entry.
- Report to {{OWNER}} when complete: who was hired, why, and where to find them.
