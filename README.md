# Genesis

> Your Claude Code, but it knows you.

**Genesis is a self-bootstrapping AI team that interviews you before it works for you.**

Clone it. Run `/genesis`. It asks you who you are, what you do, what eats your week — then builds itself around you. You walk away with a personalised team of agents, a vector-backed memory, and a workflow that already knows your projects.

It is not a framework. It is not a chatbot. It is the seed of an *operating system* for a one-person team — running on Claude Code, persistent across sessions, and capable of growing itself.

---

## What makes this different

| | Genesis | Letta | AutoGen | MetaGPT |
|---|---|---|---|---|
| Memory | Vector + dreaming + 7-wing palace | Stateful agents | Conversational only | Episodic |
| Onboarding | Interactive interview that shapes the system | None | None | None |
| Agents | Generated **per user** during onboarding | Pre-built | Pre-built roles | Pre-built (CEO, CTO, etc.) |
| Self-extension | `/hire` — system designs and onboards new agents on demand | No | Manual | No |
| Filesystem | Inbox-as-interface; the user drops a PDF, the team works | API-only | API-only | Code-focused |
| Foundation | Claude Code | Anthropic SDK | Multi-LLM | OpenAI-focused |

> Letta gives you memory. AutoGen gives you conversation. MetaGPT gives you a software company.
> **Genesis gives you a team that interviews you to figure out what *you* need, then builds itself.**

---

## What it has built

Genesis is the template of a team that already works inside a company. I built it for a Portuguese metalworking SME, where much of the routine ran on spreadsheets, retyped data, manual month-end checks and memory. I assembled a team of Claude Code agents, each with a name and a role, and handed it those problems one at a time. The rule: agents prepare, calculate, draft and check; what leaves the company or cannot be undone waits for me, or for the person who signs for it, with exceptions I chose on purpose, such as routine order confirmations. The same team went on to build Procurum, a B2B procurement startup.

### In the SME

**Quoting.** Vitor, the full-stack developer agent, and Nora, the interface agent, built a configurator that prices each line from the company's rules, with versioned parameters, and produces the PDF. An agent now reads the customer's email, prepares the quote and writes the reply as a draft in the thread, with Bruno on the wording. I check it before it leaves and approve every change to the pricing rules.

**Replies.** Bruno, the B2B communications agent, drafts replies, requests and follow-ups to customers and suppliers in their language, each with an explicit commercial goal and without committing to a deadline or a price. Tiago, the QA agent, reads every draft before it reaches my inbox. Bruno never sends; I read and send.

**Filing email.** Once I have dealt with a customer email, I move it into that customer's folder. A routine that works by rules, written by Catarina, sorts it by year and project, recognising the job from the order reference checked against the project board and the ERP; other topics sit in theme folders. It moves only what it recognises with high confidence, never deletes or renames, and logs every move with a way to undo it.

**Order intake.** For each order arriving by email, a pipeline built around Catarina, the ERP integration agent, enters it in the ERP, forwards it to production and opens it on the job board. Unclear cases go to a review queue Vitor built, and anything irreversible in the ERP stays with me. The customer then receives a confirmation in wording I approved, with figures from the ERP checked against their document; if they do not match, nothing goes out and I get an alert.

**Job management.** Every job card starts as a copy of a template carrying the process checklist. When an engineer leaves a question for the customer on a card, the system finds the email thread and Bruno drafts the question in the customer's language; the answer comes back to the card with the engineer tagged. I review and send.

**Production drawings.** Joaquim, the product CAD engineer agent, drives the CAD software through its API and takes a job from the 3D model to production drawings: assembly and part sheets, a bill of materials that reconciles with the assembly, and flat patterns for cutting. Hugo checks the weld symbols. Signature fields stay blank on purpose: the company's engineer verifies and signs before anything reaches the shop floor or a customer.

**Weld drawing validation.** Hugo, the welding engineer agent, checks whether the welding procedure covers the material, thicknesses and positions on each welded drawing, classifies findings as blocking or minor, and returns a report, a stamped PDF and a marked-up PDF for the engineer who drew it. The stamp is a recommendation; the human welding engineer signs.

**Offline robot programming.** The robot programmer submits a request to a queue; Gonçalo, the offline robot programming agent, writes or converts the program for the welding cells, and the files arrive with the assumptions to validate. Nothing runs on a real cell until the programmer has checked it on the controller and run a dry cycle.

**Production planning.** Matilde, the production engineer agent, owns the scheduling engine, which sets planned dates per operation at finite capacity, by section, with real people and machines. Every working day an agent reconciles the plan with the ERP, pushes back what was not done and logs what changed and why. The production planner decides. Running as a trial.

**Time and attendance.** Vitor and Nora built an internal web app, with Maria, the research agent, on the rules. It opens on the exceptions (missed clock-ins, hours that differ from the ERP), computes overtime by the company's rules and produces the payroll variables file. The person who runs payroll checks and exports; I decide who has access.

**Business dashboard, built and watched.** Lena, the data agent, and Nora built a dashboard on the internal network with orders, invoicing and costs by job and by customer, refreshed from the job sheets and from accounting trial balances loaded by hand. Miguel, the finance agent, analysed costs against budget during the build. Since then a heartbeat checks that the dashboard responds and that its data is fresh.

### Procurum

Procurum is a B2B procurement platform with AI, built without a hired software team. Tomas, the platform agent, owns backend, API and operations; Rui, the AI systems engineer agent, owns agents, prompts and evaluation; Alice, the product design agent, owns the design system; Nora builds the screens and Tiago tests end to end. The platform requests quotes from suppliers by email, reads the replies, compares them and sends the order, and the purchasing operator decides at every step. In progress: a new frontend, where I approve each block before the next.

### Health and money

**Health.** Biometric data, food intake, exercise and sleep flow from my phone and a wearable into a database of their own, kept apart from the team's memory, with a dashboard that shows how they evolve. Agents in clinical analysis, nutrition and exercise physiology read the data when I ask and look for patterns. None of them touches medication or makes a diagnosis.

**Trading.** The work is split by role so that nothing reaches the market on enthusiasm: market analysis, quantitative research that judges whether a signal is real, strategy and risk, and execution. The strategy agent sends every test back to research and never grades its own work. Only a strategy with a positive verdict reaches execution, which validates each order before placing it; reconciliation brakes stop execution when the state does not match. I decide when it starts, stops and restarts.

### The system looking after itself

**Heartbeats.** Scheduled routines used to die quietly. Diogo, the automation reliability agent, owns the watch, which Tomas wrote. A frequent check with no model confirms that services respond, routines ran on time, network shares are mounted and the database is intact, and opens a note per anomaly that closes itself when the evidence returns. When something fails, a local model reads the log and restarts only what died; a failure that keeps returning raises a class note so the cause gets fixed. A separate watcher emails me.

**Kaizen.** Once a week the orchestrator reads the logs, the failures and what the team has learned, looks at ideas from outside, and proposes a few concrete improvements on a board, each with what it is, why it came up and what it implies. I choose which go ahead; only those are applied.

---

## 30-second quickstart

```bash
# 1. Clone
git clone https://github.com/freskhu/genesis.git
cd genesis

# 2. Install dependencies (Python 3.11+)
pip install -r requirements.txt

# 3. Initialise the database
sqlite3 Database/team.db < Database/schema.sql

# 4. Open Claude Code in this directory
claude

# 5. Run the onboarding (this is the magic)
/genesis
```

That last command is the one that matters. The interview takes about 20 minutes. By the end, you have a personalised orchestrator, a populated memory, and a starter team of 3-5 agents that exist *because of who you are*.

---

## What you get

After `/genesis` completes, your repository contains:

- **An orchestrator** (`Team/orchestrator.md`) that knows your name, role, projects, communication style, and dealbreakers.
- **A memory layer** (MemPalace) seeded with your identity and current commitments — searchable by *meaning*, not just keywords.
- **A starter roster**: Maria (research), Sarah (HR), Lena (DBA), plus 3-5 agents you chose during the interview, each with a real name, scope, and voice.
- **A workflow**: drop a PDF in `inbox/`, get a deliverable in `outbox/`. No long prompts.
- **Skills you can run anytime**: `/hire` to grow the team, `/dream` to consolidate memory, `/kaizen` for daily improvements, `/weekly-review`, `/quarterly-review`, `/handoff`, and more.
- **Specs with checkable criteria**: for substantial work the orchestrator writes a spec in `Team/_briefs/`; each acceptance criterion becomes a row with a state. The author claims it with a pointer to the proof, someone else verifies it, and a spec without criteria is not dispatched.
- **Guardrails as hooks, each with its own test**: destructive SQL, secrets pasted into the chat, copies of databases with personal data, pattern-based kills of production processes, a second agent launched while one is still running, repeated corrections in the same session, edits piling up without a commit.
- **Rules for what never goes into shared memory**: health data, company financial figures, secrets, copies of personal-data databases, plus a ladder for reaching websites (captchas included) before asking you.

---

## How it works

```
                                ┌─────────────────────┐
   You ────type a request────►  │   Orchestrator      │
                                │   (the kernel)      │
                                └──────────┬──────────┘
                                           │ delegates
                            ┌──────────────┼──────────────┐
                            ▼              ▼              ▼
                       ┌────────┐    ┌────────┐    ┌────────┐
                       │ agent₁ │    │ agent₂ │    │ agent₃ │
                       └────┬───┘    └────┬───┘    └────┬───┘
                            │             │             │
                            ▼             ▼             ▼
                       ┌─────────────────────────────────────┐
                       │   MemPalace  ·  vector + KG  ·     │
                       │   filesystem  ·  SQLite tasks DB    │
                       └─────────────────────────────────────┘
                                           │
                                  ┌────────┴────────┐
                                  │   /dream        │
                                  │   nightly       │
                                  │   consolidation │
                                  └─────────────────┘
```

- **Orchestrator (kernel):** routes requests, never executes itself.
- **Agents (processes):** specialised, stateless, speak only when called.
- **MemPalace (memory):** vector embeddings for semantic search, knowledge graph for entity relationships, organised in *wings* (work, personal, projects).
- **Filesystem (I/O):** `inbox/` for input, `outbox/` for output.
- **Dreaming:** a nightly skill (`/dream`) that consolidates the day's memory — strengthening relevant facts, pruning stale ones.

For the full architecture, read [`docs/architecture.md`](docs/architecture.md).

---

## Anatomy of the repo

```
genesis/
├── CLAUDE.md                    # the orchestrator's system prompt (Claude reads this)
├── AGENTS.md                    # how to extend the system (per agents.md spec)
├── Team/                        # team profiles (orchestrator.md is created by /genesis)
├── outbox/                      # team deliverables for the user
├── inbox/                       # user's input files for the team
├── Database/
│   ├── team.db                  # operational SQLite (tasks, agents, activity)
│   ├── schema.sql               # full schema
│   └── migrations/              # incremental migrations
├── scripts/
│   ├── palace.py                # MemPalace CLI wrapper
│   ├── palace_audit.py          # read-only memory health audit
│   ├── spec_criteria.py         # acceptance criteria: ingest, claim, verify, close
│   ├── corrections.py           # repeat-correction nudge and its measurement
│   ├── check_refs.sh            # every path the repo names must exist
│   ├── generate_memory_hot.py   # session briefing generator
│   └── memory_tiers.py          # hot/warm/cold tier management
├── .claude/
│   ├── skills/                  # /genesis, /hire, /dream, /kaizen, etc.
│   ├── agents/                  # Maria, Sarah, Lena (core trio)
│   ├── rules/                   # data boundaries, secrets, permissions, web access
│   ├── protocols/               # session start/end, quality gate, handoff, logging
│   └── hooks/                   # guardrails, each with a .test.sh
├── docs/                        # architecture, skill writing, customising
├── LICENSE                      # Apache 2.0
└── NOTICE                       # attribution + clarification on generated code
```

---

## Customising

After `/genesis`:

- **Hire more agents:** run `/hire` and describe the gap. Maria researches the role, Sarah designs the agent, Lena registers it.
- **Add new skills:** run `/write-a-skill` to scaffold a workflow definition.
- **Reorganise memory:** edit your wings (rename, add) directly with `palace.py`.
- **Add hooks:** drop a `.sh` file in `.claude/hooks/` and reference it in `.claude/settings.json`.

The system is meant to grow. The shipped state is the *seed*, not the destination.

---

## Status & roadmap

This is **v0.1** — the public seed. Things that work:

- ☑ Genesis interview + initial roster
- ☑ MemPalace memory (vector + KG)
- ☑ Hire pipeline (Maria → Sarah → Lena)
- ☑ Inbox-driven workflows
- ☑ Skills: dream, kaizen, db-health, quality-gate, voice-gate, weekly-review, quarterly-review, handoff
- ☑ Hooks: SQL guardrails, session-stop auto-save, delegation gate, voice check
- ☑ Hooks added in 2026-11: secret brake, copy guard, correction nudge, spec criteria gate, agent throttle (warning only), kill guard, commit nudge, auto-mode warning; every hook ships with a test
- ☑ Machine-readable spec criteria, palace audit, data-boundary rules, web access ladder (see [`CHANGELOG.md`](CHANGELOG.md))

### What changed since v0.1

The seed has been running daily in a live instance since. Most of what came back is
not new features but corrections: the delegation gate now blocks until a reflective
artifact exists instead of politely reminding; the SQL guardrail stopped firing on
its own trigger words when they appear inside a data payload; `Stop` hooks no longer
fire on subagents, where they were displacing the agent's final report; memory
regeneration fails loudly instead of silently in the background. On top of that:
the **digital twin** operating model (ask the depth question, write a spec, verify
against its own acceptance criteria, deliver once), an **asymmetric quality gate**
that is mandatory for three classes of deliverable and optional for everything else,
a **voice gate** with an example banlist, and four database migrations that make
cost and procedural memory honest. The first end-to-end audit of that instance
produced seven lessons that generalise — hooks versus native events, backups,
`maxTurns`, memory-layer contracts, identifiers, probe reach, and classifiers wired
to actuators — written up in [`docs/lessons-2026-08.md`](docs/lessons-2026-08.md).

The second sync (2026-11) brought what two more months of daily use taught. The
pattern is the same as the first time: rules that depended on someone remembering
became hooks with tests; checks that could not fail (a row count on a full-text
index) were replaced by checks that measure; and the spec's acceptance criteria
stopped being a list someone reads and became rows someone has to prove. The details
are in [`CHANGELOG.md`](CHANGELOG.md).

Coming next:

- ☐ One-command installer (no manual schema/db setup)
- ☐ Templates for common professional profiles (founder, designer, researcher, dev)
- ☐ Migration tool for users who fork private and want to track upstream
- ☐ Built-in cost tracker and weekly LLM-spend report
- ☐ Documentation site

---

## Philosophy

A few opinions baked in:

1. **Personalisation > generality.** A team named "Marketing Agent" is dead on arrival. Yours has names, voices, scope.
2. **Memory > context.** Cramming context into prompts ages badly. A vector-backed palace with semantic search ages well.
3. **Filesystem > API.** Drop a file, walk away. The team picks it up. This is how humans work.
4. **One orchestrator, never two.** The user talks to one entity, which delegates. Multi-tenant chaos is not a feature.
5. **Self-extension is the point.** The system that can hire its own agents is qualitatively different from one that can't.

---

## Community

Two channels:

- 💬 **[Discussions](https://github.com/freskhu/genesis/discussions)** — *Show & Tell* (share your setup), *Ideas* (debate features), *Q&A* (ask for help), *Agent Marketplace* (share agent definitions). Informal.
- 🐛 **[Issues](https://github.com/freskhu/genesis/issues)** — bugs and concrete feature requests with scope.

### The pulse loop

Genesis is built so each user's local OS can stay connected to the swarm without drowning in noise:

```
┌─────────────────────┐         ┌─────────────────────┐
│  Your Genesis       │         │  freskhu/genesis    │
│  (local fork)       │         │  Discussions+Issues │
└──────────┬──────────┘         └──────────┬──────────┘
           │                                │
           │  /sync-upstream  ←───── code ──┤
           │  (daily, opt-in)               │
           │                                │
           │  /forum-pulse  ←──── threads ──┤
           │  (daily, opt-in,               │
           │   filtered by your palace)     │
           │                                │
           ▼                                ▼
   You see only what                Other forks see the
   matters to YOU.                  same — each filtered
                                    through their own work.
```

`/sync-upstream` keeps your code in step. `/forum-pulse` brings the *human signal* — agents others built, bugs that affect you, threads where your work is relevant.

**Five autonomy levels for `/forum-pulse`** (chosen during `/genesis`, changeable anytime):

| Level | The team can… |
|---|---|
| **0 Lurker** *(default)* | Read, propose actions. You click to post. |
| **1 Reactor** | Add emoji reactions (👍 / 🎉) on HIGH-relevance threads. |
| **2 Drafter** | Write comment drafts to `outbox/Forum Pulse/`; you publish. |
| **3 Speaker** | Post low-stakes comments directly (always signed `AI-assisted`). |
| **4 Contributor** | Open PR drafts for trivial fixes; substantive comments on Discussions. |

Every auto-post at Level 3+ carries a signature footer revealing AI assistance — honesty over engagement, no disguising agents as humans.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the bar, and [`AGENTS.md`](AGENTS.md) for how the agentic structure expects extensions.

Pull requests welcome. Use cases more welcome — the more diverse the deployments, the better Genesis gets at fitting non-template lives.

---

## License

[Apache 2.0](LICENSE) — including a patent grant. See [NOTICE](NOTICE) for attribution and an important clarification: **code generated by `/genesis` belongs to you**, unencumbered by this template's license. The Apache terms apply to the template itself, not to your derivative agents.

---

Built by [Simão Curval Ferreira](https://github.com/freskhu) for his MBA cohort. Use it. Fork it. Make it yours.
