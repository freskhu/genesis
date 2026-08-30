---
name: session-end
description: "Run the mandatory Session End Protocol (palace and twin updates, diary, activity log, kaizen backlog, lessons learned, procedural audit, memory-hot regen)"
user-invocable: true
allowed-tools: Read Bash Glob Grep
---

# Session End Protocol — wrapper

This skill is a thin wrapper. The canonical, single source of truth is:

**`.claude/protocols/session-end.md`**

Read that file and execute the steps in order:

1. Palace and twin updates (`palace.py add` / `kg-add` / `kg-invalidate`, plus `/twin-update`)
2. Diary entry (AAAK format, `palace.py diary-write`)
3. Activity log (`session_end`)
4. Kaizen backlog surface (only when 3+ `[Kaizen]` proposals have been pending >48h)
5. Lessons learned and system improvement (feedback memory / procedural memory / palace)
6. Procedural memory audit (BLOCKING — enumerate delegations, capture non-obvious patterns)
7. Regenerate memory hot (`python3 scripts/generate_memory_hot.py`)

The protocol is enforced by the `force-session-end.sh` (`Stop`) hook, which blocks
the close until lessons, procedural audit and memory-hot regeneration are
evidenced.

Do NOT duplicate or fork the step logic here — edit the protocol file instead.
Two copies of a protocol drift, and the copy the agent happens to read wins.
