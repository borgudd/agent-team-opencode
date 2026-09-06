---
name: agent-team
description: A multi-model agent team — Product Owner, Architect and Coder on Claude Opus 5, Reviewer on OpenCode (GPT) — that lives in the project as a pinned git submodule and works from separate clones, one terminal per role, coordinating only through git. /agent-team init sets up the workspace, /agent-team status shows the board, /agent-team upgrade bumps the pinned version.
argument-hint: "init [--name project] | status | upgrade"
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# agent-team

One repo, one clone per role, one terminal per clone. All communication is git. The team itself — roles, templates, launchers, rulebook — is this submodule at `.claude/skills/agent-team`, pinned per project, so two projects can run different team versions without ever touching each other.

```
<workspace>/
├── team          launcher: ./team po | architect | coder [N] | reviewer | status | log | add coder
├── po/           clone · Product Owner · Opus 5 · writes .team/backlog/  on main
├── architect/    clone · Architect     · Opus 5 · writes .team/plans/    on main
├── coder/        clone · Coder         · Opus 5 · code on feat/NNN-*, PRs, .team/notes/
└── reviewer/     clone · Reviewer      · OpenCode (GPT) · .team/reviews/ on the PR branch + gh pr review
```

Inside every clone:

```
.claude/skills/agent-team/   this submodule: SKILL.md, bin/, team/{TEAM.md,roles,templates}
AGENTS.md                    project conventions + pointer to team/TEAM.md   (OpenCode reads this)
CLAUDE.md                    "read AGENTS.md"
.team/                       team.md (human, models, pinned version) + the lanes: backlog/ plans/ notes/ reviews/
```

Status is never written — it is derived from git and GitHub (`bin/status`). Each role writes only in its own lane, so nothing conflicts. Architect, Coder and Reviewer run unattended: `bin/wait-for <role>` blocks until the board has something in their lane, so a pushed story flows through plan → PR → review with no nudging. The human talks to the PO and merges.

Arguments given: `$ARGUMENTS`

## `init`

You are being run inside the first clone, which must be named `po/` and already contain this submodule (that is how you got here). Run:

```bash
bash .claude/skills/agent-team/scripts/init.sh [--name "<project name>"]
```

It scaffolds `AGENTS.md`, `CLAUDE.md` and `.team/` if missing, commits and pushes (the commit records this skill's `git describe` version), clones `architect/`, `coder/`, `reviewer/` next to `po/` with the submodule checked out, sets each clone's git author to its role, and writes `../team`.

Then open `AGENTS.md` and fill in **Project conventions** (stack, test command, lint) from what you can see in the repo — ask only if you cannot tell. Commit and push. Tell the user, briefly:

```
cd <workspace>
./team open        # four windows; every role starts working, the three workers wait on the board
./team board       # the board, auto-refreshing
```

`./team po` etc. start a single role by hand. The Reviewer's model and permissions are pinned in `~/.config/opencode/agent-team-reviewer.json` (via `OPENCODE_CONFIG`).

## `status`

Run `.claude/skills/agent-team/bin/status` and show it.

## `upgrade`

```bash
git submodule update --remote .claude/skills/agent-team
git -C .claude/skills/agent-team describe
```

Show the user what changed (`git -C .claude/skills/agent-team log --oneline <old>..<new>`), then commit the new pointer: `team: agent-team → <version>`, push. The other clones pick it up on their next start (`bin/_start` runs `git submodule update`). Update the `team:` line in `.team/team.md` in the same commit.

## Why it is shaped like this

- **The team is a submodule, not a global install.** Version compatibility is per project: a project pins the team it was built with and upgrades when it chooses. Any fresh clone of the project has the whole team; nothing lives in `~/.claude`.
- **Separate clones.** Four sessions in one working directory step on each other the moment the Coder checks out a branch. Clones are dumb and robust; GitHub is the hub.
- **Derived status, lanes.** Story → ready, plan → planned, branch → in-progress, PR → in-review, review decision → approved / changes-requested, merged → done. PO → `backlog/`, Architect → `plans/`, Coder → code + `notes/`, Reviewer → `reviews/`. Nothing to sync, nothing to conflict on.
- **A different model reviews.** Different mistakes. Never the same family as the Coder.
- **Short role files.** Frontier models get worse with over-prescriptive instructions. Per-project tweaks go in `.team/roles/<role>.md`, which overrides the submodule's file.
- **Agents sign their work** and never pose as the human. **The human merges.**
