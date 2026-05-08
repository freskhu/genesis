---
name: inbox-process
description: "Process new files in Team Inbox: detect, flag to {{OWNER}}, process with approval, mark as done"
user-invocable: true
argument-hint: "[optional: specific filename to process]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Agent"]
---

# Inbox Processing

## Step 1 -- Detect New Files

List Team Inbox contents:
```bash
ls -la "Team Inbox/"
```

Check what's already processed:
```sql
PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;
SELECT filename FROM processed_inbox_files;
```

Compare: any file in the directory NOT in the processed list is new.

## Step 2 -- Flag to {{OWNER}}

For each unprocessed file, present to {{OWNER}} with options:
- **Index in knowledge base** -- extract content, categorize, store in knowledge_entries
- **Assign to team member** -- delegate to a specialist for analysis/action
- **File for reference** -- mark as processed without further action
- **Ignore** -- skip this file

Wait for {{OWNER}}'s decision on each file.

## Step 3 -- Process

Based on {{OWNER}}'s choice:

### If indexing in knowledge base:
1. Read the file content
2. Determine category: user, feedback, project, reference, strategy, technical
3. Delegate to Lena to insert:
```sql
INSERT INTO knowledge_entries (title, content, category, summary, added_by)
VALUES (?, ?, ?, ?, 1);
```
4. Add relevant tags

### If assigning to team member:
1. Identify the right team member
2. Delegate the task
3. Log in activity_history

### If filing for reference:
1. Just mark as processed (Step 4)

## Step 4 -- Mark as Processed (MANDATORY)

After processing each file:
```sql
INSERT INTO processed_inbox_files (filename, processed_at, notes)
VALUES (?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), ?);
```

## Rules

- Never process without {{OWNER}}'s approval
- Never delete files from Team Inbox
- Always mark processed files in the DB
- If 3+ files are being indexed, trigger `/dream` after completion
