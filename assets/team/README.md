# .team — how this works

Four agents, one human, one repo. Each role has its own clone and its own terminal. All communication is git. The human merges.

```
backlog/   stories       Product Owner (Fable 5.1)   on main
plans/     build plans   Architect (Fable 5.1)       on main
notes/     blockers      Coder (Opus 5)              on main, only when a plan fails
reviews/   PR reviews    Reviewer (Codex / GPT)      on the PR branch
roles/     what each role does — the only instructions the agents get
templates/ story / plan / note / review skeletons
bin/       launchers and the status board
```

Status is never written. `bin/status` derives it: story → `ready`, plan → `planned`, branch → `in-progress`, PR → `in-review`, GitHub review decision → `approved` / `changes-requested`, merged → `done`. Each role writes in its own folder or branch, so nothing ever conflicts.

## Running it

From the workspace root (one pane per line):

```
./team po          # talk here
./team architect   # nudge with "check the board"
./team coder       # nudge with "check the board"
./team reviewer    # nudge with "review open PRs"
./team status      # the board
./team log         # who did what, across all roles
./team add coder   # more throughput: clones coder-2/, start with ./team coder 2
```

Each launcher pulls before starting. Agents pick up work by status when started or nudged, and stop when their lane is empty. `gh auth status` must be green. Give Codex a high reasoning effort — the reviewer is where you want the thinking.

## Rules of thumb

- Stories small enough for one PR. The PO splits, the Architect refuses to plan what does not fit on a screen.
- The Reviewer is always a different model family than the Coder. That is the point.
- Agents sign what they write. Nothing in this repo pretends to be you.
- If an agent goes off the rails, the fix is almost always a shorter role file, not a longer one.
