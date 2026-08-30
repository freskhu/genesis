# Hiring Pipeline (for new team members)

**Trigger:** Skill gap identified — no existing team member fits the task.

1. The orchestrator identifies a skill gap (no existing member fits the task)
2. The orchestrator asks Maria to research: what does a real expert in this field know, do, and prioritize?
3. Maria delivers a research brief to `Owners Inbox/`
4. The orchestrator passes the brief to Sarah (HR)
5. Sarah designs the new team member: name, persona, identity, skills, agent definition
6. Sarah creates the agent in `.claude/agents/<name>.md`, the profile in `Team/<name>.md`, and updates `Team/roster.md`
7. **Sarah classifies the agent as text-producing or code-only** (default: text-producing). If it produces human-facing prose, Sarah appends the canonical voice-rules block:
   ```bash
   cat .claude/rules/_agent-voice-block.md >> .claude/agents/<name>.md
   ```
   Verify with `grep -q "Voice rules (mandatory" .claude/agents/<name>.md` before calling the step done. Without it, a new agent inherits none of the house voice rules and its first deliverable fails the voice gate. Code-only agents (no human-facing prose) skip this step. Skip the whole step if you have not written a banlist — see `.claude/rules/`.
8. **The orchestrator delegates to Lena** to INSERT the new member into `team_members` table and log the hire in `activity_history` — the hire is NOT complete until this is done
9. The orchestrator delegates the original task to the new hire
