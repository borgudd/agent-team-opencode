---
name: agent-team
description: Set up a workspace where a multi-model agent team — Product Owner and Architect on Fable 5.1, Coder on Opus 5, Reviewer on Codex (GPT) — works on one GitHub repo from separate clones, one terminal per role, coordinating only through git. Run /agent-team init <owner/repo> to create the workspace, /agent-team status for the board.
argument-hint: "init <owner/repo> [--dir path] [--name project] | status"
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# agent-team

One repo, one clone per role, one terminal per clone. All communication is git.

```
<workspace>/
├── team          launcher: ./team po | architect | coder [N] | reviewer | status | log | add coder
├── po/           clone · Product Owner · Fable 5.1 · writes .team/backlog/  on main
├── architect/    clone · Architect     · Fable 5.1 · writes .team/plans/    on main
├── coder/        clone · Coder         · Opus 5    · code on feat/NNN-*, PRs, .team/notes/
├── coder-2/      (added with ./team add coder when you want more throughput)
└── reviewer/     clone · Reviewer      · Codex     · .team/reviews/ on the PR branch + gh pr review
```

Nobody reads anyone else's working directory. Every session starts with `git pull` and ends with `git push`. Status is never written by hand — it is derived from what exists in git and on GitHub, so no two roles ever edit the same file. The human merges.

Arguments given: `$ARGUMENTS`

## `init <owner/repo>`

Creates the workspace. Needs `gh` authenticated (`gh auth status`) and a GitHub repo, empty or not.

1. If the user has no repo yet, offer to create one: `gh repo create <name> --private`. Do not create it without asking.
2. Resolve the directory this SKILL.md lives in and run:

   ```bash
   bash "<skill-dir>/scripts/init.sh" --repo <owner/repo> [--dir <workspace>] [--name "<project name>"]
   ```

   Default `--dir` is `./<repo>-team`. The script clones `po/`, scaffolds `.team/`, `AGENTS.md`, `CLAUDE.md` into it if missing, commits and pushes, then clones `architect/`, `coder/`, `reviewer/` and writes the `team` launcher. Each clone gets `git config user.name "<Role> (<model>)"` so `git log` shows who did what; the email stays the human's.
3. Open `<workspace>/po/AGENTS.md` and fill in **Project conventions** (stack, test command, lint) from what you can see in the repo. Ask only if you cannot tell. Commit and push from `po/` — the other clones pull on start.
4. Tell the user how to run it, briefly:

   ```
   cd <workspace>
   ./team po          # talk here
   ./team architect   # nudge with "check the board"
   ./team coder       # nudge with "check the board"
   ./team reviewer    # nudge with "review open PRs"
   ./team status      # the board
   ```

   One terminal pane per line. Codex should run with high reasoning effort — the Reviewer is where the thinking pays.

## `status`

Run `./team status` from the workspace, or `.team/bin/status` from inside any clone, and show the output. If neither exists, the workspace has not been set up — offer `init`.

## Why it is shaped like this

- **Separate clones, not a shared checkout.** Four sessions in one working directory step on each other the moment the Coder checks out a branch. Clones are dumb and robust; GitHub is the hub. Worktrees would be lighter but only one worktree can have `main` checked out, and two roles need it.
- **Status is derived.** Story on main → ready. Plan → planned. Remote branch → in-progress. PR → in-review; GitHub's review decision → approved / changes-requested; merged → done. Nothing to keep in sync, nothing to conflict on, and the board is always true.
- **Lanes.** PO → `backlog/`, Architect → `plans/`, Coder → code and `notes/`, Reviewer → `reviews/`. Different folders, different branches, zero merge conflicts.
- **A different model reviews.** The Reviewer makes different mistakes than the Coder. Never the same model family.
- **Short role files.** Frontier models get worse with over-prescriptive instructions. Roles say what you own and hand off, not how to code.
- **Agents sign their work** and never pose as the human. **The human merges.**

## Files

- `scripts/init.sh` — creates the workspace (clones, scaffold, launcher)
- `scripts/scaffold.sh` — copies `assets/` into the current clone; idempotent, never overwrites
- `assets/root/` → `AGENTS.md`, `CLAUDE.md`
- `assets/team/` → `.team/` (team.md, README, roles/, templates/, bin/, backlog/, plans/, notes/, reviews/)
- `assets/workspace/team` → the launcher at the workspace root

The skill is a git repo installed by `git clone` into `~/.claude/skills/agent-team`; update with `git pull`. Every scaffold records the skill version (`git describe`) in the scaffold commit and in `.team/team.md`.
