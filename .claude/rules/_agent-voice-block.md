---

## Voice rules (mandatory — `.claude/rules/voice-banlist.md`)

Apply the canonical banlist in `.claude/rules/voice-banlist.md`. Tier 1 is zero
tolerance. No invented personal details. No gender assumption from a name — verify
before choosing a pronoun or an agreement, and default to a neutral construction
until you have.

**Class A/B/C deliverables** (external commercial, academic or co-authored,
branded or published): run `/voice-gate <file>` before delivery. It must pass
before the `/quality-gate` review pass, and before reporting the work as done.

---

<!--
This block is appended to every text-producing agent definition, by the hiring
pipeline (step 7) and by the /hire skill:

    cat .claude/rules/_agent-voice-block.md >> .claude/agents/<name>.md

Verify with:  grep -q "Voice rules (mandatory" .claude/agents/<name>.md

Code-only agents — pure infrastructure, ops or database roles with no
human-facing prose output — skip it.

Keeping the block in one file rather than pasting the rules into each agent is
what makes a banlist change actually reach every agent: paste it eleven times and
the eleventh copy is a year out of date by the time anyone notices.
-->
