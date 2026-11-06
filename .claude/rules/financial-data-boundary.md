# Company financial data boundary

Drawers, `team.db`, the diary and the auto-memory are readable by every agent of the team, including the ones that write to clients, suppliers and public audiences. The owner's company figures stay in files, where only someone who goes there on purpose arrives. Shared memory gets the pointer.

## The test

> **If the agent that writes emails to clients read this, would it learn how much the company earns, owes, holds in cash, pays or charges?**

If yes, it is rewritten before saving. One line, before every write to shared memory.

## 1. Never in shared memory

**Where:** drawers and the knowledge graph; all of `team.db` (`activity_history`, `tasks`, `llm_calls`, `procedural_memory`, `spec_criteria`); the diary; the auto-memory files. Agent `HANDOFF` and `KG-FACTS` blocks count, because the orchestrator logs them in the database.

**What:**

- Margins, EBITDA, results, revenue.
- Debt, cash, treasury, equity, financing, covenants, capex.
- Cost prices, supplier prices, cost per hour, payroll.
- Values per job or per order.
- Ratios and percentages that reveal them. Roundings and orders of magnitude count.
- Coursework or case studies that use the company as the case: they count as the company.
- Figures of clients and suppliers known to the company: they leave through the same channel.

## 2. Fine to save

- Decisions without values.
- Names of line items, sheets, columns and tables.
- Generalised lessons. "Reconcile the forecast with the accountant's official source before presenting it" passes; the same lesson with the number does not.
- Technical and operational quantities: weight, thickness, lead time, order number.
- Public tax facts, with source.
- Costs of the team's own tools: API, quotas.
- Case studies about other companies, with public data.

The dry pointer is the canonical form:

> Forecast reviewed on <date>. Values in `outbox/<project>/<file>`. Decided: <decision, no values>.

## 3. Prices and quotes

**A quote sent to a client does not go in.** It stays confidential towards the other clients. The agent writing to the next client reads the palace, and one client's price in an email to another is the worst possible use; next to the cost, it also gives the margin. Quotes live in the mailbox, the ERP and the quote file. Memory gets the quote number and the pointer.

**A public price goes in, with the link next to it:** a published price list, a public procurement contract. Without a link anyone can open, it counts as confidential.

## 4. Automatic save prompts

`session-stop-save.sh`, `precompact-save.sh`, `post-delegation.sh` and the session-end protocol ask to save what the session decided. Summarising from memory a session about a forecast is exactly when figures slip in without intent. These prompts open no exception: save the decision and the file path.

## 5. On finding a figure

- **In your own write:** rewrite before saving.
- **Already saved:** report the id or name to the orchestrator, never the value. The correction is the owner's decision and follows section 4 of `.claude/rules/health-data-boundary.md`: rewrite, re-embed, verify by `MATCH`, backup in `Database/backups/`.
- **To decide something:** a figure read in a drawer is not a source. Open the file.

## 6. Limits

**There is no mechanical block.** `palace.py add` accepts a figure. The rule lives on behaviour and on the reminders of section 4. The `[LENS]` prefix does not protect: it only exists in the owner wings and rooms.

**Scope: the owner's company.** Side projects and personal investing are outside this rule unless the owner extends it.

## Do not touch

Files with values stay where they are: `outbox/` is their place. Prices in an email to a client belong to whoever writes that email and to the quality gate. Where databases with personal data live is `.claude/rules/personal-data-db-access.md`.
