# Contributing to Genesis

Thanks for the interest. Genesis grows through forks, ideas, and concrete contributions. Here's how each path works.

## Forks (the most common case)

Genesis is a *template* — you're expected to fork it, run `/genesis`, and customise. That fork is yours. You don't need to upstream anything.

If you fork *and want to keep up with upstream changes*, the `/sync-upstream` skill (introduced in v0.1) checks `freskhu/genesis` daily and helps you cherry-pick what's relevant. See [`.claude/skills/sync-upstream/SKILL.md`](.claude/skills/sync-upstream/SKILL.md).

## Ideas and discussion (no commitment)

Open a [Discussion](https://github.com/freskhu/genesis/discussions). The four categories:

- **Show & Tell** — share your customised setup, your hires, your workflow. Other users learn from concrete examples.
- **Ideas** — propose features, debate architecture, sketch what's missing. No expectation that anyone will build it.
- **Q&A** — ask for help, share answers.
- **Agent Marketplace** — share an agent definition you wrote and want others to reuse. Include the role, scope, and a one-paragraph rationale.

Discussions are **the right place for "wouldn't it be cool if..."**.

## Issues (committed work)

Open an [Issue](https://github.com/freskhu/genesis/issues) when you have a concrete bug or a feature with clear scope.

Use the issue templates:
- **🐛 Bug report** — something is broken.
- **✨ Feature request** — a defined feature you (or someone) intends to build.
- **🤝 Agent share** — submit an agent definition for inclusion in the core templates.

Issues should be actionable. If it's exploratory, prefer Discussions.

## Pull Requests

PRs welcome, with the bar:

1. **One purpose per PR.** Don't mix a bug fix, a new skill, and a doc rewrite.
2. **Sanitisation.** No personal data in commits — names, emails (except the author's own), API keys, project specifics. The repo is a template.
3. **Skill discipline.** New skills under `.claude/skills/` follow the convention in [`docs/writing-skills.md`](docs/writing-skills.md). One sentence in the description that triggers the skill. SKILL.md under 100 lines.
4. **Backwards compat.** Don't rename things in `Database/schema.sql`, `scripts/palace.py`, or `CLAUDE.md` without coordinating — those touch every fork.
5. **Tests where reasonable.** New scripts get a smoke test. New skills get a documented dry-run.

DCO is not enforced but a Signed-off-by line is welcome.

## Coding conventions

- Python 3.11+. Type hints encouraged, not mandatory.
- SQL: explicit column lists in INSERT, parameterised queries (no string interpolation).
- Bash: `set -euo pipefail` at top of scripts.
- Markdown: GitHub-flavored, sentence case in headings except proper nouns.
- All user-facing copy in English by default. The user's preferred language is configured during `/genesis` and the orchestrator translates.

## Reviews

I (Simão) review PRs. Most of the time within a few days. If silent for >2 weeks, ping the PR.

## Code of conduct

Be civil, be specific, be useful. Disagreement is welcome; performance-art rudeness is not. Standard CNCF code of conduct applies.

## License

By contributing you agree your contribution is licensed under [Apache 2.0](LICENSE), the same as the repo. Significant contributors can be added to NOTICE on request.
