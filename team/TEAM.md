# How this team works

This repository is worked on by a small team of AI agents plus one human (named in `.team/team.md`).
Everyone reads the project's `AGENTS.md` first, then this file.
Roles live in `$TEAM/roles/`, templates in `$TEAM/templates/`, where `$TEAM` = `.claude/skills/agent-team/team`.
The team itself is a git submodule pinned to a version; the project's own files are `AGENTS.md`, `CLAUDE.md` and `.team/`.

## The team

| Role | Runs on | Lane (the only place you write) | Never |
|---|---|---|---|
| Product Owner | Opus 5 | `.team/backlog/` on main; merges approved topic PRs | plans, code, forcing a merge |
| Architect | Opus 5 | `.team/plans/` on main | production code |
| Coder | Sonnet 5 | code + tests on `feat/NNN-*`, PRs, `.team/notes/` on main | scope changes, merging |
| Reviewer | Sonnet 5 | `.team/reviews/` on the PR branch, reviews on GitHub | rewriting the code |
| Human | — | main-critical merges | — |

Each role works in its own clone of this repo, in its own terminal, unattended: Architect, Coder and Reviewer sit in a loop on `bin/wait-for <role>`, which returns the moment the board has something in their lane. Nobody looks at anyone else's working directory. **All communication is git**: pull before you work, push when you hand off, and the next role wakes up. The human talks to the PO; the PO merges approved story PRs, and the human merges main-critical work.

## How work flows

```
story → plan → branch + PR → review → fixes → PO merges (human: main-critical)
```

1. **PO** writes `.team/backlog/NNN-slug.md` on main. Pushes.
2. **Architect** pulls, inspects the code, writes `.team/plans/NNN-slug.md` on main. Pushes.
3. **Coder** pulls, branches `feat/NNN-slug`, implements, tests, pushes, opens a PR with `gh pr create`.
4. **Reviewer** pulls, `gh pr checkout`, gates on CI and currency, reviews, writes `.team/reviews/NNN-slug.md` (with `verdict:`) on the PR branch, pushes. That push is the decision; a `gh pr review --comment` mirrors it on GitHub.
5. **Coder** pulls the branch, fixes, pushes.
6. **PO** merges the approved, green, current PR (`gh pr merge --squash --delete-branch`); main-critical work stays the human's merge.

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
| it says `verdict: approve` | `approved` — PO merges |
| PR merged | `done` |
| the PR branch's latest PR CI run failed, errored, timed out, was cancelled, or never ran | `ci-fails` — Reviewer's turn (requeue or hand back) |
| the latest main run failed and its commit names story NNN | `needs-fix` — Coder repairs Red main |
| a declared dependency (story or plan `depends-on:`) is not `done` yet | `blocked` — nobody (wait; unblocks itself) |
| `not-before:` on the story is a date still in the future | `held` — nobody (wait; unblocks itself on the date) |
| `depends-on:` names a story that does not exist | `dep-missing` — PO fixes the declaration |
| declared dependencies form a loop (including a story that depends on itself) | `dep-cycle` — PO fixes the declaration |
| `not-before:` does not parse as `YYYY-MM-DD` | `date-invalid` — PO fixes the declaration |

A story or plan can declare `depends-on: 001, 002` — one line, comma-separated, three-digit IDs. Only `done` satisfies a dependency; a dependency that GitHub cannot be queried for, or that is itself `blocked`, counts as not done, so a blocked story never degrades into work. A dependency discovered while planning goes in the plan's frontmatter (never by editing the story).

A story can declare `not-before: YYYY-MM-DD` in its frontmatter (the PO's call, story-only — a plan cannot set it, same as `urge:`) to hold it out of every lane until that date: no role is offered it and it is still listed, showing what date it is waiting for. The date is compared to `date +%F` on the machine running `bin/status` — that host's own local calendar day, evaluated once per run; there is no timezone field, so if the host's day is not good enough for a given story, say so when filing it rather than assuming one. A date already today or in the past has no effect — the story behaves exactly as if the line were absent. A story that is both `blocked` and held shows `blocked`, since the dependency is the thing a person might act on and the date resolves itself; a story depending on a held one is `blocked by: NNN(held)`. Terminal rows (`done`/`closed`/`cancelled`) are never held. A date that does not parse as `YYYY-MM-DD` is `date-invalid` rather than hidden or held forever — a day-of-month beyond the real calendar (`2026-02-30`) is accepted and simply holds until the next calendar date lexicographically past it.

A story can declare `urge: true` in its frontmatter (the PO's call, story-only — a plan cannot set it) to jump the queue: `bin/wait-for` offers a role its urgent rows before its non-urgent ones, ID order otherwise unchanged. Urgency orders *within* a role's own precedence classes; it never lets a `planned` story jump a `changes-requested` one, and never overrides `blocked` — a declared dependency still wins. Anything but `true`/`yes`/`1` (a bare `urge:`, a typo, a word) means not urgent, and the story is still listed. The board (`bin/status`) shows which rows are urgent; `bin/wait-for` is what actually reorders them.

Nothing is allowed to rot quietly. A row that has sat in an actionable state for more than `STALE_HOURS` (default 24, env-overridable) gets a `(stale Nh)` marker on its title — age comes from the PR's last update, or the story/branch commit time otherwise. The marker is informational: the lane owner still acts, and when the Reviewer's lane is empty it runs one budgeted sweep — requeues cancelled CI runs, and names the worst stale rows in its next review comment so no story stalls invisibly.

Because every role writes in a different folder or on a different branch, there is nothing to conflict on. `git log -- .team/` is the team's history; `git log --author=Coder` is one role's.

## Rules

- IDs are three digits: the next free number in `.team/backlog/`. The slug is the same across story, plan, branch, note and review.
- One story = one plan = one branch = one PR. Too big for one PR? The PO splits it.
- Stay in your lane. If you need something from another role, leave it where they look (see the table), push, and stop.
- `git pull --rebase` before you push. If a push is rejected, pull and push again — do not force.
- Sign your work. Text an agent writes on the human's behalf (commit messages, PR bodies, review comments) ends with `— <Role> (<model>) on behalf of <human>`, the human being whoever `.team/team.md` names. Never pose as the human.
- Keep it short. These agents know how to code. This file coordinates; it does not teach craft.
