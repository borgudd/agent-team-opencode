# agent-team

A Claude Code skill that runs a multi-model agent team on a GitHub repo:
Product Owner and Architect on Fable 5.1, Coder on Opus 5, Reviewer on Codex (GPT).
The team lives **in the project** as a pinned git submodule. One clone per role, one terminal per clone, all communication through git. Status is derived, never written. The human merges.

See [SKILL.md](SKILL.md) for the design and [team/TEAM.md](team/TEAM.md) for the rulebook the agents get.

## New project

One command, from nothing to a running workspace:

```bash
curl -sL https://raw.githubusercontent.com/fltman/agent-team/main/new-project.sh | bash -s -- myproj
```

It creates the GitHub repo if needed (private by default, `--public` to change), makes `./myproj-team/`, clones `po/`, pins the newest tagged team version as a submodule, scaffolds, pushes, clones `architect/`, `coder/`, `reviewer/`, writes `./team` — and opens the four roles, each in its own window: a 2×2 grid of Terminal windows on macOS, a 2×2 tmux session elsewhere (`--no-open` to skip). From a clone of this repo, `./new-project.sh myproj` does the same.

```
cd myproj-team
./team open        # (again) PO top-left, Architect top-right, Coder and Reviewer below; --tmux for tmux anywhere
./team board       # the board, refreshed every 30 s — park it in a corner
./team po          # or start any single role by hand — talk to PO first; ask it to fill in Project conventions in AGENTS.md
./team status      # the board, once
./team log         # who did what
./team add coder   # more throughput: coder-2/, started with ./team coder 2
```

`./team` is a three-line shim; the launcher itself lives in the submodule, so it upgrades with the team.

By hand, the same thing is: `gh repo create`, `git clone … po`, `git submodule add … .claude/skills/agent-team`, then `/agent-team init` inside `po/`.

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
