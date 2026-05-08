---
name: forum-pulse
description: Read the upstream Genesis community (Discussions + Issues), cross-reference with the user's MemPalace, and surface what's actually relevant to *their* work. The connective tissue between the user's local Agentic OS and the swarm.
---

# Forum Pulse

Most online communities die because nobody has time to read everything. This skill is the user's filter — every day (or on demand), it scans the upstream community at `freskhu/genesis` and surfaces only what *matters to them*.

The signal: **the user's own work, captured in MemPalace, is the lens.** Generic noise gets filtered. Relevant agents, threads, bugs, or proposals get a spotlight.

---

## Step 0 — Pre-flight

1. Ensure `gh` CLI is authenticated:
   ```bash
   gh auth status
   ```
   If not — instruct the user: `gh auth login`. Skill cannot proceed without it.
2. Confirm MemPalace is reachable:
   ```bash
   python3 scripts/palace.py status
   ```
3. Read `Database/genesis_config.json` for `last_pulse_check` (timestamp of previous run). If missing, default to "7 days ago".

---

## Step 1 — Fetch new community activity

Pull everything since `last_pulse_check`:

```bash
SINCE="2026-05-01T00:00:00Z"  # from config

# Discussions (use GraphQL — REST API doesn't expose discussion content well)
gh api graphql -f query='
{
  repository(owner: "freskhu", name: "genesis") {
    discussions(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number title bodyText updatedAt category { slug }
        comments(first: 5) { nodes { bodyText author { login } } }
      }
    }
  }
}' > /tmp/discussions.json

# Issues
gh issue list --repo freskhu/genesis --state all --limit 50 \
  --json number,title,body,labels,state,updatedAt,comments > /tmp/issues.json
```

Filter to items updated **after** `last_pulse_check`.

---

## Step 2 — Cross-reference with the user's palace

For each discussion/issue title + body:

1. Run a semantic search against the user's palace:
   ```bash
   python3 scripts/palace.py search "{title + first 200 chars of body}" --mode vector --limit 3
   ```
2. Capture the top match's distance score and which wing/room it came from.
3. **Relevance bucket:**
   - **HIGH:** semantic distance < 1.5 — the user has clearly worked on something semantically close.
   - **MEDIUM:** distance 1.5–2.2 — adjacent topic, might be useful.
   - **LOW:** distance > 2.2 — generic interest only.

Also boost relevance for:
- **Agent Marketplace category** — always at least MEDIUM (agents are reusable).
- **Issues affecting the user's pinned skills** (read `Team/orchestrator.md` for which skills the user pinned during /genesis).
- **Breaking change announcements** — always HIGH.

---

## Step 3 — Synthesise the digest

Format:

```
Forum pulse — 2026-05-15 · 7 days · 12 new threads

  ━━ HIGH RELEVANCE ━━
  💬 #42  Discussion · Agent Marketplace
      "Lucia v2 — better LinkedIn voice tuning"
      → matches your "Curval marketing" wing (semantic dist 0.87)
      → 3 comments, last from @joana 2h ago

  🐛 #29  Issue · BUG · open
      "/dream consolidates wrong tier when palace > 10k drawers"
      → you have 12,400 drawers (matches the trigger condition)
      → fix in PR #31, ready to merge

  ━━ MEDIUM RELEVANCE ━━
  💡 #38  Discussion · Ideas
      "Cross-OS agent transfer protocol"
      → adjacent to your /sync-upstream usage
      → conversational, no commitment

  ━━ LOW (showing top 2) ━━
  💬 #45  General · "What hardware do you run on?"
  💡 #44  Polls · "Default language for new installs"

  Total noise filtered: 6 threads.
```

---

## Step 4 — Propose actions

For each HIGH item, propose a concrete action and ask for confirmation:

### Agent share (Marketplace)
> "Want me to **import** the agent definition from #42 into `.claude/agents/`? I'll review it first, sanitise, and put it under your control."

If yes:
- Fetch the agent block from the discussion thread.
- Write to `.claude/agents/{name}.md`.
- Run `/hire`'s validation step (Lena registers in `team_members`, Sarah reviews scope).
- Don't auto-activate — just install.

### Issue affecting the user
> "Issue #29 directly hits a condition in your setup. Want me to:
>  (a) subscribe you to the thread (so you see updates),
>  (b) cherry-pick the fix from PR #31 now via /sync-upstream,
>  (c) leave it for now?"

### Discussion alignment
> "You worked on Y last week. There's a discussion #38 exactly on Y. Want me to draft a comment with your perspective for you to review and post?"

If yes:
- Draft comment in `Owners Inbox/Forum Pulse/draft-comment-{discussion-number}.md`.
- Include: the user's relevant past work (citations to palace), a one-paragraph contribution.
- User reviews and posts manually with `gh discussion comment {n}` (the skill never posts on the user's behalf without explicit click-through).

---

## Step 5 — Persist

```bash
# Update config
jq '.last_pulse_check = now | tojson' Database/genesis_config.json > /tmp/cfg.json
mv /tmp/cfg.json Database/genesis_config.json
```

Log:
```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary)
VALUES (1, 'forum_pulse', 'system',
        'Pulse run: N new threads, M high relevance, K actions proposed.');
```

Save the digest itself to MemPalace (so future searches can reference what was seen):
```bash
python3 scripts/palace.py add --wing community --room reference --hall hall_events \
  --content "{full digest text}" --source "forum-pulse"
```

---

## Step 6 — Optional: schedule daily

If the user opted into auto-sync during `/genesis` (see `auto_sync_enabled`), suggest also scheduling forum-pulse daily:

```
/schedule daily 09:00 /forum-pulse
```

---

## Anti-patterns

- **Never post comments or issues without explicit user confirmation per-action.** Drafting is fine; posting is theirs.
- **Never import agents without showing the source.** Marketplace agents can be malicious; always show the SKILL.md content first.
- **Don't surface every thread.** The whole point is filtering. If everything is "MEDIUM", drop the digest entirely and tell the user "nothing relevant this run."
- **Don't double-count.** If a thread was already proposed in a previous run, skip it unless something material changed (new comment from user the user knows, new label, state change).
- **Respect rate limits.** GitHub API has 5000 req/h authenticated — cache responses for 1h on repeat calls in same session.

---

## When the user has no palace yet

If they just ran `/genesis` and palace is sparse, the relevance check has nothing to cross-reference. In that case:
- Show top 5 trending threads regardless of relevance.
- Mention: "I'll get smarter at this once you've had the system for a few weeks — your work history is the filter."

---

## Output format reminder

Always end with the action list (not just the digest). The digest is for context; the actions are for the user to decide.

```
Actions proposed:
  [1] Import agent Lucia v2 from #42
  [2] Cherry-pick fix from PR #31 (resolves #29)
  [3] Draft comment for discussion #38
  [4] Skip everything

Pick numbers (or 'skip'):
```
