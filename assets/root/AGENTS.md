# {{PROJECT_NAME}} — agent team

This repository is worked on by a small team of AI agents plus one human ({{HUMAN}}).
Everyone reads this file first: Claude Code sessions and Codex alike.
Role instructions live in `.team/roles/`. Models in `.team/team.md`.

## The team

| Role | Runs on | Lane (the only place you write) | Never |
|---|---|---|---|
| Product Owner | Fable 5.1 | `.team/backlog/` on main | plans, code |
| Architect | Fable 5.1 | `.team/plans/` on main | production code |
| Coder | Opus 5 | code + tests on `feat/NNN-*`, PRs, `.team/notes/` on main | scope changes, merging |
| Reviewer | Codex (GPT) | `.team/reviews/` on the PR branch, reviews on GitHub | rewriting the code |
| Human | — | merging | — |

Each role works in its own clone of this repo, in its own terminal. Nobody looks at anyone else's working directory. **All communication is git**: start every work session with `git pull`, end every handoff with `git push`. The human merges. Always.

## How work flows

```
story → plan → branch + PR → review → fixes → human merges
```

1. **PO** writes `.team/backlog/NNN-slug.md` on main. Pushes.
2. **Architect** pulls, inspects the code, writes `.team/plans/NNN-slug.md` on main. Pushes.
3. **Coder** pulls, branches `feat/NNN-slug`, implements, tests, pushes, opens a PR with `gh pr create`.
4. **Reviewer** pulls, `gh pr checkout`, reviews, writes `.team/reviews/NNN-slug.md` on the PR branch, pushes, posts the same review with `gh pr review`.
5. **Coder** pulls the branch, fixes, pushes.
6. **Human** merges.

## Status is derived, never written

Nobody edits a status field. The board (`.team/bin/status`) reads it off git and GitHub:

| If | then the story is |
|---|---|
| story exists, no plan | `ready` — Architect's turn |
| plan has `verdict: needs-split` | `needs-split` — PO's turn |
| plan exists, no `feat/NNN-*` branch | `planned` — Coder's turn |
| a `.team/notes/NNN-*` file is newer than the plan | `needs-replan` — Architect's turn |
| branch exists, no PR | `in-progress` — Coder |
| PR open, no decision, or commits after the last review | `in-review` — Reviewer's turn |
| GitHub says changes requested | `changes-requested` — Coder's turn |
| GitHub says approved | `approved` — human merges |
| PR merged | `done` |

Because every role writes in a different folder or on a different branch, there is nothing to conflict on. `git log -- .team/` is the team's history; `git log --author=Coder` is one role's.

## Rules

- IDs are three digits: the next free number in `.team/backlog/`. The slug is the same across story, plan, branch, note and review.
- One story = one plan = one branch = one PR. Too big for one PR? The PO splits it.
- Stay in your lane. If you need something from another role, leave it where they look (see the table), push, and stop.
- `git pull --rebase` before you push. If a push is rejected, pull and push again — do not force.
- Sign your work. Text an agent writes on the human's behalf (commit messages, PR bodies, review comments) ends with `— <Role> (<model>) on behalf of {{HUMAN}}`. Never pose as the human.
- Keep it short. These agents know how to code. This file coordinates; it does not teach craft.

## Project conventions

<!-- Fill in at init. Everything the whole team must know and nothing else. -->

- Stack:
- Run tests:
- Lint / format:
- Default branch: main

## If you are Codex

You are the **Reviewer**. Read `.team/roles/reviewer.md` and do that job. You do not implement features.
