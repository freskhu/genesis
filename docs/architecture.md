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

## Governance — capability over vigilance

Five layers describe what the system *is*. Three principles describe how it stays safe as it gains autonomy. Each was reached the hard way, by watching where vigilance-based rules fail.

**Govern by capability, not by vigilance.** A rule the orchestrator must remember to follow ("always ask before doing X") fails on the one confused night it forgets. Where a refusal guards a *narrow, downstream* capability, the stronger move is to remove the capability itself: the orchestrator holds no wire to the sensitive endpoint, so the bad action is impossible by construction, not prevented by a check that has to pass every time. Not every refusal converts. The orchestrator's broad authority to read, propose, and route cannot be removed without removing the orchestrator, and that residual stays policy. The value of the audit is the sort: which refusals guard a capability narrow enough to cut into a missing wire, and which are the irreducible core where vigilance is spent deliberately.

**Govern by risk of propagation, not by file type.** Not every write is equally dangerous. The one that matters is the write that loads back into the agent every session, the always-on context, because that is what a poisoned entry propagates through. So the control follows the propagation surface, not the storage format: additive writes to the store are free and ungated; the always-loaded index is bounded and diff-controlled; irreversible destruction (`DROP`, `DELETE`-without-`WHERE`, `TRUNCATE`) is hard-stopped at the boundary. An inert archive nobody loads carries none of that weight and needs none of that ceremony.

**Model tier is a cost axis, not a safety axis.** Which model runs a task is a budget decision. Safety comes from separation of duties and a human trigger on irreversible actions, not from how capable the model is. The two are independent: a cheaper model does not make an irreversible action safer, and a premium one does not make it safe to automate.

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
