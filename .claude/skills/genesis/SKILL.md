---
name: genesis
description: First-run onboarding — interview the user deeply, then build a personalised Agentic OS around them. Run this once when you clone the repo. Generates the owner profile, customises the orchestrator, and proposes the initial agent roster based on the user's actual work, not a template.
---

# Genesis — First Run

This skill is the **only** thing the user runs the first time they clone the repo. It is the `/init` of Genesis. Skip it and the system has no idea who is sitting in front of it.

## Operating principle

The interview is **conversational, adaptive, and visible**. The user must feel that every answer is being absorbed and shaping the system. We do **not** ask 30 questions in a flat form. We branch. We summarise. We show the artefacts being built **during** the interview, not at the end.

Anthropic's own Claude Code best practices recommend this: ask the user one thing at a time using `AskUserQuestion`, branch on their answers, and confirm understanding before moving on.

---

## Step 0 — Pre-flight

Before any question:

1. Confirm the database is initialised. Run:
   ```bash
   sqlite3 Database/team.db ".tables" | grep -q team_members || \
     sqlite3 Database/team.db < Database/schema.sql
   ```
2. Confirm MemPalace is reachable:
   ```bash
   python3 scripts/palace.py status
   ```
   If not, instruct the user: `pip install mempalace && mempalace init`.
3. Confirm Genesis hasn't already run:
   ```sql
   SELECT COUNT(*) FROM team_members WHERE role = 'Owner';
   ```
   If `> 0`, ask the user: "Genesis has already run for *{name}*. Run again? (re-doing this overwrites your profile.)"

---

## Step 1 — Identity (open the door)

Ask one question at a time. Wait for each answer. Reflect back before moving on.

**Q1.** "Hi. Before I do anything for you, I need to know who you are. What's your name, and what do you call yourself professionally — title, role, the answer you'd give at a dinner with strangers?"

**Q2.** "Where do you work, and what does the place do?" (If they're a founder/owner, ask about the venture instead.)

**Q3.** "How long have you been doing this?" (Career anchor — calibrates language register.)

**After Q1-Q3:** mirror back. "So you are *{name}*, *{role}* at *{org}*, *{years}* in. Got it." Save to a working draft. Show them.

---

## Step 2 — Background (the why behind the what)

**Q4.** "How did you get here? One sentence per chapter — education, first real job, biggest pivot."

**Q5.** "What were you almost? What did you nearly become but didn't?" (Surfaces values and decisions.)

**Q6.** "What do other people misunderstand about your work?" (Calibrates how the system explains itself.)

---

## Step 3 — Current work (what fills your day)

**Q7.** "Walk me through a normal Tuesday. Hour by hour."

**Q8.** "List the projects, ventures, courses, or commitments you're running right now. Don't curate — give me everything that takes brain space."

**Q9.** "For each one — what stage is it at, who else is involved, and what does success look like by the end of the year?"

**As Q7-Q9 land:** start populating MemPalace wings. Show the user:
> "I'm creating wings in your memory: `{wing_1}`, `{wing_2}`, `{wing_3}`. Each one is a separate space the system can search later. Add or rename any of these:"

**Q10.** "Anything I missed? Any side project, hobby, obsession, or recurring obligation?"

---

## Step 4 — The pain (where AI earns its keep)

**Q11.** "What part of your week do you actively dread? The thing you'd pay to make disappear."

**Q12.** "What gets repetitive? What do you find yourself explaining over and over?"

**Q13.** "What can't you do alone but also can't justify hiring a person for?"

**This is where agent suggestions start forming.** As the user talks, build a working list of agent candidates. Don't show them yet.

**Q14.** "If you had a junior person sitting next to you for 10 hours a week, what would you have them do?"

---

## Step 5 — Style and standards

**Q15.** "Pick the language combo: English-only, English+native, native-only. (Native = your first language; if the system needs to translate, name it.)"

**Q16.** "How do you prefer feedback — direct and blunt, structured with caveats, or warm and discursive?"

**Q17.** "Three things that immediately make you not trust an AI's output." (Negative examples calibrate guardrails.)

**Q18.** "Anything else about how you work that I should know? Quirks, constraints, dealbreakers."

---

## Step 5b — Stay in sync with upstream

**Q19.** "Genesis is open source and gets updates — new skills, better hooks, bug fixes. Want me to check daily and tell you what changed? You can review and apply, ignore, or pause anytime."

If yes:
- Set `auto_sync_enabled = true` in `Database/genesis_config.json`.
- Record current commit SHA as `last_synced_commit`.
- Mention `/sync-upstream` skill — runs the daily check manually.
- Optional: instruct user to add a daily reminder via `/schedule` to invoke `/sync-upstream` automatically.

If no:
- Set `auto_sync_enabled = false`.
- Mention they can run `/sync-upstream` manually whenever they're curious.

Either way: write the choice to the orchestrator profile so future sessions remember.

---

## Step 5c — Listen to the swarm

**Q20.** "Other Genesis users share agents, ideas, and bug fixes through the upstream community. Want me to read it daily and tell you only what's relevant to *your* work? I cross-reference your palace — generic noise gets filtered."

If no: set `forum_pulse_enabled = false`. They can still run `/forum-pulse` manually whenever curious.

If yes — follow up:

**Q20a.** "How autonomous should the team be in the forum?"

| Pick | What happens |
|---|---|
| **0 — Lurker** *(default, safest)* | Reads, proposes actions to you. Never posts or imports anything without a click. |
| **1 — Reactor** | Adds emoji reactions (👍 / 🎉) on HIGH-relevance threads automatically. |
| **2 — Drafter** | Writes comment drafts to `Owners Inbox/Forum Pulse/`. You review and post manually. |
| **3 — Speaker** | Posts low-stakes comments directly ("+1 with context", "I see this too on a 12k drawer setup"). Always signed `(AI-assisted by your Genesis instance)`. |
| **4 — Contributor** | Opens PR drafts for typo/doc fixes. Comments substantively when palace gives strong signal. Always signed. |

Each level inherits the previous. Defaults to **0**. User can change later by editing `Database/genesis_config.json` field `forum_pulse_level` or via the orchestrator.

Persist to config:
```json
{
  "forum_pulse_enabled": true,
  "forum_pulse_level": 0,
  "last_pulse_check": "2026-05-08T22:00:00Z"
}
```

Optional: schedule daily via `/schedule daily 09:00 /forum-pulse`.

**Crucial guardrail:** Level 3+ posts ALWAYS carry a signature footer revealing AI assistance. Honesty over engagement. Never disguised as human.

---

## Step 6 — Synthesis (show the artefact)

Now the system writes (and **shows the user, live**) two artefacts:

### 6a — `Team/orchestrator.md`

The orchestrator's brief — populated from Q1-Q18. Includes:
- Owner identity, role, organisation
- Communication preferences (language, tone, feedback style)
- Active projects/wings
- Working patterns
- Dealbreakers and trust signals

The orchestrator reads this on every session. **It is the single most important artefact.**

### 6b — Owner identity in MemPalace

Add to wing `owner` (or whatever the user named their personal wing):
```bash
python3 scripts/palace.py add --wing owner --room identity --hall hall_facts \
  --content "{full identity narrative built from Q1-Q18}"
```

Plus a knowledge graph fact:
```bash
python3 scripts/palace.py kg-add "{owner_name}" "is" "{role}"
python3 scripts/palace.py kg-add "{owner_name}" "works_at" "{org}"
# ...one per project:
python3 scripts/palace.py kg-add "{owner_name}" "runs" "{project_name}"
```

**Show the user the artefacts on screen.** Ask: "Anything wrong here? Any sentence I should rewrite before we move on?"

---

## Step 7 — Propose the initial roster

Based on the pain points (Q11-Q14) and the projects (Q8-Q9), generate **3 to 5 agent candidates**. For each one, present:

- **Proposed name** (real first name, single word)
- **Role** (one line)
- **Why this agent** (one paragraph linking to specific things the user said)
- **What they'd own** (concrete responsibilities)

Example output format for the user:

> Based on what you told me, I'd suggest these first hires:
>
> **1. Lucia — Marketing Communications**
>    *Why:* You said writing newsletters and LinkedIn posts eats your Monday morning.
>    *Owns:* drafts in your voice, ships through approval queue in `Owners Inbox/Marketing/`.
>
> **2. André — Personal Finance Analyst**
>    *Why:* You mentioned reconciling personal+business spending takes 2h every weekend.
>    *Owns:* parses statements, flags anomalies, generates monthly summary.
>
> **3. ...** (continue)

Ask: "Hire which of these now? Pick numbers. We can always hire more later via `/hire`."

For each chosen agent, **delegate to Sarah** (HR) to create the agent file, profile, and database row. Use the `/hire` skill.

---

## Step 8 — First win

Before closing, propose **one concrete task** that one of the new hires can do **right now**. Examples:

- Lucia: "Want me to draft your next LinkedIn post about *{recent thing user mentioned}*?"
- André: "Want me to set up the file conventions for next month's reconciliation?"
- A code agent: "Want me to scaffold the structure for *{project user mentioned}*?"

The user must experience the team **working** before they close the terminal. This is the activation moment.

---

## Step 9 — Persist + close

1. Mark Genesis as run:
   ```sql
   INSERT INTO team_members (name, role, agent_path, profile_path, joined_at)
   VALUES ('{owner_name}', 'Owner', NULL, 'Team/orchestrator.md',
           strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
   INSERT INTO activity_history (actor_id, action, entity_type, summary)
   VALUES (1, 'genesis_completed', 'system',
           'Genesis interview completed for {owner_name}. Initial roster: {agent_names}.');
   ```
2. Regenerate memory hot:
   ```bash
   python3 scripts/generate_memory_hot.py
   ```
3. Final message to user:
   > "Genesis is done. Your team has {N} agents including the core trio (Maria, Sarah, Lena). The orchestrator now knows who you are. Run `/session-start` whenever you open a new conversation, and the system will pick up where it left off."

---

## Anti-patterns

**Do NOT:**
- Ask all questions in a single block (wall-of-text death).
- Generate placeholder agents ("Marketing Agent", "Coding Agent"). Names matter.
- Skip the synthesis (Step 6) — the user must SEE what was inferred.
- Auto-hire without confirmation.
- Continue if the user gives short, evasive answers — pause and ask "is this a bad time?".
- Use generic stock phrasing in the user's profile. Echo their words back.

## When to bail out

If the user clearly doesn't want to do the interview right now:
- Save partial state to MemPalace as a draft (`hall_events`, room `genesis_partial`).
- Tell them: "No problem. Run `/genesis --resume` when you have 20 minutes."

---

## Output at end

Write a HANDOFF block:

```
HANDOFF — Genesis run for {owner_name}
- Profile saved: Team/orchestrator.md
- MemPalace wing: owner
- Agents hired: {list}
- First task delegated: {task or "none"}
- Next step suggested: {what user should do tomorrow}
```
