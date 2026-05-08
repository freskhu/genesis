---
name: sync-upstream
description: Check the Genesis upstream repo (freskhu/genesis) for new commits, classify each one (additive / breaking / cosmetic), recommend whether to apply, and merge only with user confirmation. Run daily if the user opted in during /genesis.
---

# Sync upstream

This skill keeps a forked Genesis in step with `freskhu/genesis` without surprising the user. It never auto-merges. It always shows what changed and waits for explicit confirmation.

---

## Step 0 — Pre-flight

1. Check git is set up and there's an `upstream` remote pointing at `freskhu/genesis`. If not, add it:
   ```bash
   git remote get-url upstream 2>/dev/null || \
     git remote add upstream https://github.com/freskhu/genesis.git
   ```
2. Read `Database/genesis_config.json` to get `last_synced_commit`. If file doesn't exist, create with current `HEAD` SHA and a fresh-install timestamp.
3. Confirm working tree is clean. If dirty, abort and tell the user to commit or stash first.

---

## Step 1 — Fetch and diff

```bash
git fetch upstream main
NEW_COMMITS=$(git log "${LAST_SYNCED_COMMIT}..upstream/main" --oneline)
```

If `NEW_COMMITS` is empty — tell the user "Already up to date." and exit.

Otherwise, count how many new commits and which paths changed:

```bash
git log "${LAST_SYNCED_COMMIT}..upstream/main" --pretty=format:"%h|%s" --name-status
```

---

## Step 2 — Classify each commit

For each commit, read the diff and classify into one of three buckets:

| Class | Heuristic | Default action |
|---|---|---|
| **Additive** | New skill file, new hook, new doc, new agent template — no existing file deleted or signature changed | RECOMMEND APPLY |
| **Breaking** | Schema migration, removed file, changed function signature, changed CLAUDE.md fundamentals | FLAG REVIEW — do not apply without explicit user OK |
| **Cosmetic** | Typo fixes, README copy edits, comment improvements | RECOMMEND APPLY |

To detect:
- **Additive:** `git diff --name-status` shows only `A` (added) lines in `.claude/skills/`, `.claude/hooks/`, `docs/`, `Database/migrations/`.
- **Breaking:** `M` or `D` on `CLAUDE.md`, `Database/schema.sql`, `scripts/palace.py`, or any agent file the user has customised (check against the user's git log).
- **Cosmetic:** changes to `README.md`, `*.md` in `docs/`, comments only (no code lines changed).

---

## Step 3 — Build the report

Format as a table the user can scan in 30 seconds:

```
Genesis upstream — 4 new commits since 2026-05-08

  abc1234  Add /mine-conversations skill                       [ADDITIVE]   apply ✓
  def5678  Fix typo in docs/architecture.md                    [COSMETIC]   apply ✓
  ghi9012  Refactor palace.py: rename TEAM_DB → DB_PATH        [BREAKING]   review ⚠
  jkl3456  Add NOTICE clause about commercial use              [COSMETIC]   apply ✓

3 of 4 commits are recommended to apply. 1 needs your review.
```

For BREAKING commits: include a 3-line summary of WHY it's breaking. Example:

> `ghi9012` renames `TEAM_DB` to `DB_PATH` in `scripts/palace.py`. If you've forked palace.py or have skills referencing `TEAM_DB`, they'll fail. Recommend: review the diff, update your forks, then merge.

---

## Step 4 — Confirm + apply

Ask the user one of:

1. **Apply all recommended (skip the breaking one)** — applies the 3 additive/cosmetic, leaves the breaking commit unmerged with a TODO note.
2. **Apply everything (including breaking)** — full merge.
3. **Apply nothing** — only update `last_synced_commit` so we don't ask again about these specific commits.
4. **Show me a specific diff** — `git show {sha}` for any commit.

When the user confirms applies:

```bash
# Cherry-pick the chosen commits in order, OR merge upstream/main if applying all
git merge upstream/main
# (or)
git cherry-pick {sha1} {sha2} {sha3}
```

Update `genesis_config.json`:
```json
{
  "last_synced_commit": "{new_HEAD_SHA}",
  "last_sync_check": "2026-05-08T22:30:00Z",
  "auto_sync_enabled": true,
  "skipped_commits": ["ghi9012"]
}
```

Log to `activity_history`:
```sql
INSERT INTO activity_history (actor_id, action, entity_type, summary)
VALUES (1, 'upstream_synced', 'system',
        'Synced N commits from freskhu/genesis main. Skipped: {list}.');
```

---

## Step 5 — If anything fails

- **Merge conflict:** abort the merge, show the user the conflicting files, suggest `/handoff` to package the state for a clean resolution session.
- **Network / GitHub down:** save state, retry on next run.
- **Upstream removed a file the user customised:** flag prominently, never silently delete.

---

## Anti-patterns

- **Never auto-apply breaking commits.** Even if the user said "yes apply all" once, breaking commits always re-confirm.
- **Never overwrite user-customised files** without showing the diff.
- **Don't pretend to understand a commit you couldn't classify.** When in doubt, tag `[UNCLEAR]` and ask the user.
- **Don't run more than once a day** unless the user explicitly asks. Daily is enough; chasing every commit is noise.

---

## Quick CLI for power users

If the user prefers raw git, point them to:

```bash
git fetch upstream main
git log HEAD..upstream/main --oneline
git diff HEAD upstream/main -- path/of/interest
git merge upstream/main          # take everything
git cherry-pick <sha>            # take one commit
```

The skill exists so users *don't have to* — but advanced users can drive it themselves.
