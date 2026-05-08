# Install

Step-by-step. ~5 minutes.

## Prerequisites

- **Python 3.11+** (`python3 --version`)
- **SQLite 3.40+** (`sqlite3 --version`) — comes with macOS by default
- **[Claude Code](https://claude.com/claude-code)** installed and authenticated
- **Git** (`git --version`)

## 1. Clone

```bash
git clone https://github.com/freskhu/genesis.git
cd genesis
```

## 2. Install Python dependencies

The memory layer (vector + KG) runs locally — no cloud, no telemetry — through `scripts/palace.py`. It needs three Python packages:

```bash
pip install -r requirements.txt
```

Installs `apsw`, `sqlite-vec`, and `sentence-transformers`. The first run of `palace.py` downloads the embedding model (`paraphrase-multilingual-mpnet-base-v2`, ~1GB) into your local cache.

## 3. Initialise the operational database

```bash
sqlite3 Database/team.db < Database/schema.sql
```

Verify:

```bash
sqlite3 Database/team.db ".tables"
# expected: team_members, tasks, activity_history, llm_calls, drawers, kg_entities, ...
```

Then verify the palace works:

```bash
python3 scripts/palace.py status
```

## 4. Set environment variables (optional)

If you want to override defaults, create `.env`:

```bash
GENESIS_OWNER_NAME=YourName
```

Most defaults work without configuration.

## 5. Open Claude Code

```bash
claude
```

In the session, the orchestrator should greet you and notice you have not yet run `/genesis`.

## 6. Run the onboarding

```
/genesis
```

This is the only command that matters. It will interview you for ~20 minutes, then build the orchestrator profile, the memory seed, and the initial roster.

When it finishes, run `/session-start` and you're live.

---

## Troubleshooting

### `palace.py` complains about a missing `~/.mempalace/palace`
Run `mempalace init`. If MemPalace isn't installed, install it (Step 2).

### `sqlite3` says "no such table: team_members"
You skipped Step 3. Run the schema bootstrap.

### `/genesis` doesn't appear in Claude Code's slash menu
Restart Claude Code in the project root. Skills are discovered on session start.

### Token / cost warnings
Genesis logs every Claude API call to `llm_calls`. Run `sqlite3 Database/team.db "SELECT SUM(cost_usd) FROM llm_calls;"` to see your spend at any time.

### Hooks aren't firing
Check `.claude/settings.json` references the hook scripts. On macOS, ensure `.sh` files have `chmod +x`.

---

## Uninstalling

To wipe everything:

```bash
rm -rf ~/.mempalace
rm Database/team.db
```

To preserve memory but reset the operational DB:

```bash
rm Database/team.db
sqlite3 Database/team.db < Database/schema.sql
```
