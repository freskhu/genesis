---
name: weekly-review
description: "Structured weekly check-in: scorecard, wins, losses, priority check, next week's 3 focuses, energy check. Takes 15 minutes. Use when user wants a weekly review, weekly check-in, or mentions 'weekly review'."
---

# Weekly Review

Structured 15-minute weekly check-in that replaces vague anxiety with clarity.

## Before Starting

Load context from MemPalace:
```bash
python3 scripts/palace.py search "owner priorities quarterly goals" --limit 5
python3 scripts/palace.py search "weekly review" --wing owner --limit 3
```

Check for previous reviews to track continuity.

## The Review (Conversational, Not a Form)

### 1. Scorecard (2 min)

Ask for 3-5 key metrics. For each: this week's value, trend vs last week, on track for quarterly target? Flag anything that moved more than 10%.

### 2. Wins (2 min)

Ask: "What went well this week?" Force them to name wins -- this is pattern recognition, not fluff. Probe: "Why did that work? Way to do more of it?"

### 3. Losses & Lessons (3 min)

Ask: "What didn't go well? Where did you waste time?" Then: **"What will you do differently next time?"** A loss without a lesson is just a bad week.

If same issue appears in multiple reviews, flag it: "This is the Nth week you've mentioned [X]. Symptom of something bigger?"

### 4. Priority Check (3 min)

For each quarterly priority: progress this week, status (on track / at risk / stalled), blockers.

Hard question: **"Did you spend the majority of your time on these priorities, or did other things eat your calendar?"**

### 5. Next Week's Focus (3 min)

**"If next week could only have 3 priorities, what are they?"** Three. Not five.

For each: what does "done" look like? First action Monday morning? What could prevent it?

### 6. Energy Check (2 min)

**"Scale 1-10, how's your energy?"** This is data, not therapy. A 4 three weeks running means burnout incoming. If low: is it a win needed, a decision avoided, a hire needed, or a day off?

## Output

Generate clean review document and save:
```bash
python3 scripts/palace.py add --wing owner --room reports --hall hall_events --content "[review content]"
```

## Rules

1. **15 minutes, not 60.** If something needs deeper discussion, suggest `/strategic-sparring`.
2. **Continuity matters.** Reference previous reviews. Accountability without judgment.
3. **Three priorities, not thirteen.** Push back.
4. **Don't let them skip wins.** Founders who only review problems burn out.
5. **Patterns over incidents.** One bad week is noise. Three is signal.
6. **Energy check is non-negotiable.** Skip metrics before skipping this.
7. **End with clarity.** They should know exactly what Monday morning looks like.
