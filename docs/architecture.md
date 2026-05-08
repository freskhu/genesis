# Architecture

Genesis is built on five layers. Understand them and you understand why everything else makes sense.

## Layer 1 — Orchestrator (the kernel)

The orchestrator is one entity. It is the single point of contact for the user, defined in `CLAUDE.md` and personalised in `Team/orchestrator.md` after `/genesis`.

It does **not** execute work. It routes, plans, delegates, logs. Every conversation flows through it.

When the user types a request, the orchestrator silently classifies it into one of five routes:

- **R1 (Direct):** Quick answer, no agent.
- **R2 (Self-direct):** Small edit, the orchestrator does it itself with Read/Edit/Bash.
- **R3 (Single agent):** Clear specialist fit — delegate.
- **R4 (Pipeline):** Multi-step or research-heavy — present plan, then execute.
- **R5 (Parallel):** Independent sub-tasks — fan out.

This routing is silent. The user never hears "this is route 3."

## Layer 2 — Agents (the processes)

Agents are specialised personalities. Each one has:

- A real first name (Maria, not "Researcher Agent").
- A defined scope (one role, one voice).
- A system prompt in `.claude/agents/{name}.md`.
- A row in `team_members`.

Agents are **stateless**. They only know what the orchestrator tells them in each invocation. State lives in MemPalace and the database.

The shipped trio (Maria, Sarah, Lena) are *meta-agents* — they exist to help the user grow their own team. The user's domain agents are hired during `/genesis` and via `/hire`.

## Layer 3 — Memory (MemPalace)

MemPalace is the persistent memory layer. It uses:

- **Vector embeddings** for semantic search (find by meaning, not keyword).
- **A knowledge graph** for entity relationships (who works where, who built what).
- **A drawer system** organised by *wings*, *rooms*, and *halls*.

### Wings
A wing is a top-level namespace. Default wings: `owner`, `team`, `work`, `personal`. The user can rename or add wings to match their life.

### Rooms
A room is a semantic category within a wing. Examples: `identity`, `decisions`, `architecture`, `research`, `protocols`, `cases`, `reports`, `preferences`.

### Halls
A hall classifies the *type* of memory:
- `hall_facts` — decisions made.
- `hall_events` — sessions, milestones, deployments.
- `hall_discoveries` — insights, findings.
- `hall_preferences` — habits, opinions.
- `hall_advice` — recommendations, how-tos.

A drawer is a specific entry. `palace.py add` creates a drawer, classified by wing/room/hall.

### Dreaming
Every so often (typically nightly), `/dream` runs:
1. **Orient** — survey what's happened recently.
2. **Gather** — collect new facts.
3. **Consolidate** — strengthen what's been accessed.
4. **Prune** — demote what's stale.

The output is a refreshed memory state with hot/warm/cold tiers. Hot tier loads first into context.

## Layer 4 — Filesystem (I/O)

The filesystem is the user-facing interface. Two folders matter:

- `Team Inbox/` — the user drops files here. The team picks them up via `/inbox-process`.
- `Owners Inbox/` — the team places deliverables here. The user reviews and acts.

Both folders are intentional. They mirror how a human team works: drop a brief on someone's desk, they leave the result on yours.

Sub-projects get their own folder: `Owners Inbox/Marketing/`, `Owners Inbox/Project-X/`.

## Layer 5 — Database (operational state)

`Database/team.db` (SQLite) holds operational data:

- `team_members` — the roster.
- `tasks` — open work.
- `activity_history` — every action (audit trail).
- `deliverables` — what was produced and where.
- `processed_inbox_files` — what's already been handled.
- `llm_calls` — every Claude API call (token counts, cost).
- `procedural_memory` — patterns the system has learned.
- `agent_diary` — agents' own working notes.

The DB is for **operational** state. Knowledge and memory live in MemPalace.

## How a request flows

```
User: "Find me three suppliers in Portugal that ship in <2 weeks."
  │
  ▼
Orchestrator
  │ classifies → R3 (single agent: researcher)
  │ searches MemPalace for prior work on this
  │ delegates to Maria
  ▼
Maria
  │ does research
  │ writes findings
  │ writes diary entry to MemPalace
  ▼
Orchestrator
  │ extracts key findings
  │ saves to MemPalace (work / research / hall_discoveries)
  │ logs llm_calls + activity_history
  │ returns deliverable path to user
  ▼
User: receives `Owners Inbox/Suppliers-PT/2026-05-08-shortlist.md`
```

That's it. No black boxes, no magic. Five layers, each doing one thing well.
