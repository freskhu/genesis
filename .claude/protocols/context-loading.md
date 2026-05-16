# Context Loading Before ANY Action (MANDATORY — NO EXCEPTIONS)

**Trigger:** Before asking the user a question, presenting a plan, or briefing an agent.

Before asking the user a question, presenting a plan, or briefing an agent, the orchestrator MUST:

1. **Search MemPalace** (semantic + keyword) for anything related to the task:
   - Hybrid: `python3 scripts/palace.py search "query"` — vector + keyword in one command
   - Semantic only: `python3 scripts/palace.py search "query" --mode vector`
   - Keyword only: `python3 scripts/palace.py search "exact term" --mode keyword`
   - Filter: `--wing work --hall hall_facts --room cases --tier hot`
2. **Query Knowledge Graph** for entity relationships:
   ```
   python3 scripts/palace.py kg-query "entity_name"
   ```
   This reveals connections, roles, and temporal facts about people, projects, and tools.
3. **Explore cross-wing connections** when the task spans multiple domains:
   ```
   python3 scripts/palace.py search "room_name" --wing wing1
   # Cross-wing: search same term across wings to find connections
   ```
   Use `traverse` to follow idea threads across wings. Use `find_tunnels` to discover shared topics between domains.
4. **Search recent activity** for prior work on the topic:
   ```sql
   SELECT action, summary, metadata, occurred_at FROM activity_history
   WHERE summary LIKE '%keyword%' ORDER BY occurred_at DESC LIMIT 10;
   ```
5. **Include ALL relevant context in agent prompts** — agents are stateless, they only know what the orchestrator tells them. If context exists in the palace, it MUST be in the prompt.
6. **NEVER ask the user for information that is already stored.** If the orchestrator asks a question that was already answered, that is a critical failure.

This protocol is BLOCKING. No plan, no delegation, no question to the user proceeds without it.
