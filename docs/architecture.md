# Architecture

Genesis is built on five layers. Understand them and you understand why everything else makes sense.

## Layer 1 — Orchestrator (the kernel)

The orchestrator is one entity. It is the single point of contact for the user, defined in `CLAUDE.md` and personalised in `Team/orchestrator.md` after `/genesis`.

It does **not** execute work. It routes, plans, delegates, logs. Every conversation flows through it.

When the user types a request, the orchestrator silently classifies it into one of
four routes:

- **R1 (Direct):** Quick answer, no agent. Execute immediately. R1 is read-only: an edit, a write, or any change of state is R3 at minimum, dispatched to the owner of that category (see the ownership table in `CLAUDE.md`).
- **R3 (Single agent):** Clear specialist fit — one line to the user, mini-brief in the dispatch, delegate. No plan ritual. If the task is *sensitive* — it touches money, reaches an external recipient, alters the system's own configuration, or is irreversible — ask the depth question first and run the quality gate before delivery.
- **R4 (Pipeline):** Multi-step, ambiguous, or research-heavy — ask the depth question, write a spec, then proceed. Show the spec only for high-risk or externally-bound work.
- **R5 (Parallel):** Independent sub-tasks — ask the depth question, write a spec, get an OK, then fan out.

This routing is silent. The user never hears "this is route 3."

When torn between R3 and R4, pick R3: less overhead. When unsure whether something
is sensitive, treat it as sensitive — that costs one line.

## The operating model — digital twin

The orchestrator works as the user's digital twin and quality buffer. The user
sees finished, verified work; the iteration with the team happens on the
orchestrator's side. The user is not the one chasing agents or catching errors.

The internal loop, invisible to the user:

1. **Ask depth first.** On any substantial request, the orchestrator asks up front:
   go deep and interrogate the request, or proceed directly? The *user* chooses the
   clarification depth. The orchestrator does not decide it unilaterally, and does
   not guess in silence. Trivial R1 work skips this.
2. **Spec.** For substantial or multi-agent work, write a spec file in
   `Team/_briefs/` from `_TEMPLATE.md`: objective, acceptance criteria, scope in and
   out, pinned inputs, constraints, decisions, open questions, team and sequence.
   The agents read it while working. Its acceptance criteria are the verification
   checklist in step 4 — the same list, deliberately. A single clear task gets an
   inline mini-brief instead; trivial work gets nothing.
3. **Agents save their own work.** The agent writes its deliverable to
   `Owners Inbox/` and returns a path plus its decisions, not the document body.
4. **Verify.** Does the file exist? Does it match the brief? Are the facts confirmed
   against source? Did anything get invented?
5. **Critique and iterate.** Request changes from the agent, or route through the
   quality gate. Repeat until the definition of done is met.
6. **Deliver once, when done.** With a cover note: what it is, what was decided,
   what had to be assumed.

**Subjective work is the exception.** For anything where the answer is taste —
voice, visual direction, positioning — do not iterate in the dark. Send a one-line
direction check early ("going this way, confirm?"), get the direction agreed, then
run autonomously to the end. A confirmed direction up front beats guessing someone's
taste in a private loop.

**The honest boundary.** This model guarantees *verified, complete, correct* —
which are objective properties. It does not guarantee the user will love it. Taste
is calibrated at the depth question and the early direction check, not by infinite
internal rework.

The user's visibility points are exactly three: the depth question (one line), the
spec approval (only for large or sensitive work), and the early direction check
(only for subjective work). Everything else they see finished.

## The quality gate — asymmetric by design

Not everything deserves the same review. The cost of voice or brand drift in
owner-voice, co-authored, and published material is high and hard to reverse once
it has left the building. The cost of an extra review pass on internal code is
delivery friction with little upside.

So the mandatory second pass fires for exactly three classes:

- **Class A** — owner-voice, external commercial (client and supplier email, quotations)
- **Class B** — co-authored or academic prose the user will sign
- **Class C** — branded, published content

Everything else gets one optional line in the cover note ("want a QA pass before
this goes out?") and proceeds if the user declines or does not answer.

A blanket "review everything" rule reads as rigour and behaves as a tax: it slows
every delivery equally, so people route around it, and it stops protecting the
cases that needed it. Full protocol in `.claude/protocols/quality-gate.md`.

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

The output is a refreshed memory state with hot/warm/cold tiers. The hot tier loads
first into context — which makes it the one number worth watching, because anything
hot is paid for on every single session.

`/dream` never deletes on its own initiative. It proposes prune candidates and
waits for a human OK. A maintenance job with delete permission and no human in the
loop is one bad heuristic away from erasing the memory it exists to protect.

### The lens/citable boundary

Owner and identity content carries a confidentiality classification. This is a
confidentiality boundary, not a context-budget concern: it governs what may leave
the team and reach a third party.

- **lens** — informs an agent's reasoning ONLY. Private framing, strategy, personal
  context, financial posture, negotiation stance. It must never appear verbatim, or
  in a disclosing paraphrase, in anything sent to a client, a supplier, a public
  audience, or an examiner. Use it to think; do not quote it.
- **citable** — cleared for external use.

**Default is lens.** A drawer is citable only when its content's first line is the
literal sentinel `CITABLE:`. No schema change is involved — the sentinel is read at
retrieval time, and `palace.py search` prefixes `[LENS]` on results that lack it, so
the consuming agent never has to infer the classification. Promotion to citable is a
deliberate, per-drawer act, never a bulk operation.

Safe-by-default matters here because the failure is asymmetric: over-classifying
costs a sentence the agent could have used, under-classifying puts private context
in someone else's inbox.

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

---

## What experience has changed

`docs/lessons-2026-08.md` collects seven findings from the first end-to-end audit of
a live instance: hooks versus native runtime events, database backup, `maxTurns` by
tier, the contract between memory layers, identifiers that encode the wrong measure,
probes with no reach, and classifiers wired to an actuator. They are the reasons
several of the design choices above are the way they are.
