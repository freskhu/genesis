---
name: session-start
description: "Run the mandatory Session Start Protocol (memory-hot, inbox, pending tasks, kaizen backlog, dream check, session tracking)"
user-invocable: true
allowed-tools: Read Bash Glob Grep
---

# Session Start Protocol — wrapper

This skill is a thin wrapper. The canonical, single source of truth is:

**`.claude/protocols/session-start.md`**

Read that file and execute Steps 0–5 in order:

0. Regenerate and read `.claude/memory-hot.md`
1. Inbox check (`Team Inbox/` against `processed_inbox_files`)
2. Pending tasks (`SELECT * FROM v_open_tasks;`)
3. Kaizen backlog surface (only when 3+ `[Kaizen]` proposals have been pending >48h)
4. Dream check (run `/dream` if due)
5. Log `session_start` in `activity_history`

Invoke `/session-start` manually at the start of each session. There is no
auto-firing hook: an earlier `UserPromptSubmit` gate was removed because it fired
in every Claude Code window opened anywhere inside the project tree and broke
unrelated ones. The protocol file explains the failure in full.

Do NOT duplicate or fork the step logic here — edit the protocol file instead.
Two copies of a protocol drift, and the copy the agent happens to read wins.
