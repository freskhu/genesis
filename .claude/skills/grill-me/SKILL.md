---
name: grill-me
description: "Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions 'grill me'."
---

# Grill Me — Stress-Test a Plan

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Pipeline Position

| Step | Command | What It Does |
|------|---------|-------------|
| 1a | **`/grill-me`** + `/write-a-prd` | **Manual path — interactive interview, then PRD** |
| 1b | `/shape` | Fast path — auto-grill + PRD in one shot |
| 2 | `/prd-to-issues` | Break the PRD into vertical-slice GitHub issues |
| 3 | `/ralph` | Implement each sub-issue with TDD + code review |
