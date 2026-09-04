# agent-team

A Claude Code skill that sets up a multi-model agent team on a GitHub repo:
Product Owner and Architect on Fable 5.1, Coder on Opus 5, Reviewer on Codex (GPT).
One clone per role, one terminal per clone, all communication through git.
Status is derived from git and GitHub, never written. The human merges.

See [SKILL.md](SKILL.md) for the design, `assets/root/AGENTS.md` for the rulebook the agents get.

## Install

```bash
git clone git@github.com:<you>/agent-team.git ~/.claude/skills/agent-team
```

Restart Claude Code if it was running. `/agent-team` now shows up in the slash menu.

## Update

```bash
git -C ~/.claude/skills/agent-team pull
```

Projects record which version scaffolded them in `.team/team.md`.

## Use

```
/agent-team init <owner/repo>    # create a workspace next to where you are
/agent-team status               # the board
```

Then, from the workspace:

```
./team po          # talk here
./team architect   # nudge with "check the board"
./team coder       # nudge with "check the board"
./team reviewer    # nudge with "review open PRs"
./team status
```

## Layout

```
SKILL.md              what Claude reads when you run /agent-team
scripts/init.sh       creates the workspace: clones, scaffold, launcher
scripts/scaffold.sh   copies assets/ into a clone; idempotent
assets/root/          AGENTS.md, CLAUDE.md  → repo root
assets/team/          → .team/  (roles, templates, bin, lanes)
assets/workspace/team → the ./team launcher
```

## Changing the team

Role behaviour lives in `assets/team/roles/*.md` (for new projects) and in each project's `.team/roles/` (for that project). Keep them short; if an agent misbehaves, the fix is usually fewer instructions, not more.
