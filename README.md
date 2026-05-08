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
- **A workflow**: drop a PDF in `Team Inbox/`, get a deliverable in `Owners Inbox/`. No long prompts.
- **Skills you can run anytime**: `/hire` to grow the team, `/dream` to consolidate memory, `/kaizen` for daily improvements, `/weekly-review`, `/quarterly-review`, `/handoff`, and more.

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
- **Filesystem (I/O):** `Team Inbox/` for input, `Owners Inbox/` for output.
- **Dreaming:** a nightly skill (`/dream`) that consolidates the day's memory — strengthening relevant facts, pruning stale ones.

For the full architecture, read [`docs/architecture.md`](docs/architecture.md).

---

## Anatomy of the repo

```
genesis/
├── CLAUDE.md                    # the orchestrator's system prompt (Claude reads this)
├── AGENTS.md                    # how to extend the system (per agents.md spec)
├── Team/                        # team profiles (orchestrator.md is created by /genesis)
├── Owners Inbox/                # team deliverables for the user
├── Team Inbox/                  # user's input files for the team
├── Database/
│   ├── team.db                  # operational SQLite (tasks, agents, activity)
│   ├── schema.sql               # full schema
│   └── migrations/              # incremental migrations
├── scripts/
│   ├── palace.py                # MemPalace CLI wrapper
│   ├── generate_memory_hot.py   # session briefing generator
│   └── memory_tiers.py          # hot/warm/cold tier management
├── .claude/
│   ├── skills/                  # /genesis, /hire, /dream, /kaizen, etc.
│   ├── agents/                  # Maria, Sarah, Lena (core trio)
│   └── hooks/                   # SQL guardrails, session-end auto-save
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
- ☑ Skills: dream, kaizen, db-health, weekly-review, quarterly-review, handoff
- ☑ Hooks: SQL guardrails, session-stop auto-save

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

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the bar, and [`AGENTS.md`](AGENTS.md) for how the agentic structure expects extensions.

Pull requests welcome. Use cases more welcome — the more diverse the deployments, the better Genesis gets at fitting non-template lives.

---

## License

[Apache 2.0](LICENSE) — including a patent grant. See [NOTICE](NOTICE) for attribution and an important clarification: **code generated by `/genesis` belongs to you**, unencumbered by this template's license. The Apache terms apply to the template itself, not to your derivative agents.

---

Built by [Simão Curval Ferreira](https://github.com/freskhu) for his MBA cohort. Use it. Fork it. Make it yours.
