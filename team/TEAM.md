# How this team works

This repository is worked on by a small team of AI agents plus one human (named in `.team/team.md`).
Everyone reads the project's `AGENTS.md` first, then this file.
Roles live in `$TEAM/roles/`, templates in `$TEAM/templates/`, where `$TEAM` = `.claude/skills/agent-team/team`.
The team itself is a git submodule pinned to a version; the project's own files are `AGENTS.md`, `CLAUDE.md` and `.team/`.

## The team

| Role | Runs on | Lane (the only place you write) | Never |
|---|---|---|---|
| Product Owner | Opus 5 | `.team/backlog/` on main | plans, code |
| Architect | Opus 5 | `.team/plans/` on main | production code |
| Coder | Sonnet 5 | code + tests on `feat/NNN-*`, PRs, `.team/notes/` on main | scope changes, merging |
| Reviewer | Sonnet 5 | `.team/reviews/` on the PR branch, reviews on GitHub | rewriting the code |
| Human | — | merging | — |

Each role works in its own clone of this repo, in its own terminal, unattended: Architect, Coder and Reviewer sit in a loop on `bin/wait-for <role>`, which returns the moment the board has something in their lane. Nobody looks at anyone else's working directory. **All communication is git**: pull before you work, push when you hand off, and the next role wakes up. The human talks to the PO and merges. Always.

## How work flows

```
story → plan → branch + PR → review → fixes → human merges
```

1. **PO** writes `.team/backlog/NNN-slug.md` on main. Pushes.
2. **Architect** pulls, inspects the code, writes `.team/plans/NNN-slug.md` on main. Pushes.
3. **Coder** pulls, branches `feat/NNN-slug`, implements, tests, pushes, opens a PR with `gh pr create`.
4. **Reviewer** pulls, `gh pr checkout`, reviews, writes `.team/reviews/NNN-slug.md` (with `verdict:`) on the PR branch, pushes. That push is the decision; a `gh pr review --comment` mirrors it on GitHub.
5. **Coder** pulls the branch, fixes, pushes.
6. **Human** merges.

## Status is derived, never written

Nobody edits a status field. The board (`$TEAM/../bin/status`, or `./team status` from the workspace) reads it off git and GitHub:

| If | then the story is |
|---|---|
| story exists, no plan | `ready` — Architect's turn |
| plan has `verdict: needs-split` | `needs-split` — PO's turn |
| plan exists, no `feat/NNN-*` branch | `planned` — Coder's turn |
| a `.team/notes/NNN-*` file is newer than the plan | `needs-replan` — Architect's turn |
| branch exists, no PR | `in-progress` — Coder |
| PR open, no review file yet, or code commits after the last review | `in-review` — Reviewer's turn |
| `.team/reviews/NNN-*` on the PR branch says `verdict: request-changes` | `changes-requested` — Coder's turn |
| it says `verdict: approve` | `approved` — human merges |
| PR open and its head commit has a completed failing check, or it conflicts with main | `ci-fails` — Coder's turn, whatever the review verdict just said (checked after it, overriding it, even `approved`) |
| this story's merge turned main CI red | `needs-fix` — Coder's turn (overrides `done`, `approved`, `in-review`, `changes-requested`, `in-progress`, `planned`, `needs-replan`) |
| PR merged | `done` |
| a declared dependency (story or plan `depends-on:`) is not `done` yet | `blocked` — nobody (wait; unblocks itself) |
| `depends-on:` names a story that does not exist | `dep-missing` — PO fixes the declaration |
| declared dependencies form a loop (including a story that depends on itself) | `dep-cycle` — PO fixes the declaration |

A pending or `UNKNOWN` check/mergeable state counts for nothing — only a completed failure, or a literal `CONFLICTING`, flips the row. A later red run on the same head (a re-run after a fix) flips it back to the Coder even after `approved`.

A story or plan can declare `depends-on: 001, 002` — one line, comma-separated, three-digit IDs. Only `done` satisfies a dependency; a dependency that GitHub cannot be queried for, or that is itself `blocked`, counts as not done, so a blocked story never degrades into work. A dependency discovered while planning goes in the plan's frontmatter (never by editing the story).

A story can declare `urge: true` in its frontmatter (the PO's call, story-only — a plan cannot set it) to jump the queue: `bin/wait-for` offers a role its urgent rows before its non-urgent ones, ID order otherwise unchanged. Urgency orders *within* a role's own precedence classes; it never lets a `planned` story jump a `changes-requested` one, and never overrides `blocked` — a declared dependency still wins. Anything but `true`/`yes`/`1` (a bare `urge:`, a typo, a word) means not urgent, and the story is still listed. The board (`bin/status`) shows which rows are urgent; `bin/wait-for` is what actually reorders them.

Because every role writes in a different folder or on a different branch, there is nothing to conflict on. `git log -- .team/` is the team's history; `git log --author=Coder` is one role's.

## Rules

- IDs are three digits: the next free number in `.team/backlog/`. The slug is the same across story, plan, branch, note and review.
- One story = one plan = one branch = one PR. Too big for one PR? The PO splits it.
- Stay in your lane. If you need something from another role, leave it where they look (see the table), push, and stop.
- `git pull --rebase` before you push. If a push is rejected, pull and push again — do not force.
- Sign your work. Text an agent writes on the human's behalf (commit messages, PR bodies, review comments) ends with `— <Role> (<model>) on behalf of <human>`, the human being whoever `.team/team.md` names. Never pose as the human.
- Keep it short. These agents know how to code. This file coordinates; it does not teach craft.
