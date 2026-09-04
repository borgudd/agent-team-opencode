# agent-team

A Claude Code skill that runs a multi-model agent team on a GitHub repo:
Product Owner and Architect on Fable 5.1, Coder on Opus 5, Reviewer on Codex (GPT).
The team lives **in the project** as a pinned git submodule. One clone per role, one terminal per clone, all communication through git. Status is derived, never written. The human merges.

See [SKILL.md](SKILL.md) for the design and [team/TEAM.md](team/TEAM.md) for the rulebook the agents get.

## New project

```bash
gh repo create myproj --private                      # or use an existing repo
mkdir myproj-team && cd myproj-team
git clone git@github.com:me/myproj.git po && cd po
git submodule add git@github.com:me/agent-team.git .claude/skills/agent-team
claude
> /agent-team init
```

`init` scaffolds the project files, pushes, clones `architect/`, `coder/`, `reviewer/` next to `po/`, and writes `../team`. Then:

```
cd ..
./team po          # talk here
./team architect   # nudge with "check the board"
./team coder       # nudge with "check the board"
./team reviewer    # nudge with "review open PRs"
./team status      # the board
./team log         # who did what
./team add coder   # more throughput: coder-2/, started with ./team coder 2
```

## Upgrading a project's team

Inside any clone: `/agent-team upgrade` — or by hand, `git submodule update --remote .claude/skills/agent-team`, commit, push. Every project records its pinned version in `.team/team.md` and in the scaffold commit.

## Layout

```
SKILL.md          what Claude reads when you run /agent-team
bin/              po architect coder reviewer  — launchers (pull, pick role file, start)
                  status                       — the board, derived from git + GitHub
team/TEAM.md      the rulebook every agent reads
team/roles/       product-owner architect coder reviewer
team/templates/   story plan note review
assets/           per-project files init writes: AGENTS.md, CLAUDE.md, .team/
scripts/          init.sh, scaffold.sh
workspace/team    the ./team launcher
```

## Changing the team

For every future project: edit `team/roles/*.md` here, commit, tag. For one project: drop a file in that project's `.team/roles/<role>.md`; the launcher prefers it over the submodule's. Keep roles short — if an agent misbehaves, the fix is usually fewer instructions, not more.
