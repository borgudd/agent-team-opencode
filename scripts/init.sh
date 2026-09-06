#!/usr/bin/env bash
# agent-team init — run from inside the first clone (po/) after adding the submodule.
#
#   mkdir myproj-team && cd myproj-team
#   git clone git@github.com:me/myproj.git po && cd po
#   git submodule add git@github.com:me/agent-team.git .claude/skills/agent-team
#   bash .claude/skills/agent-team/scripts/init.sh [--name "Project"]      # or /agent-team init in claude
#
# Result (siblings of po/):
#   ../team          launcher
#   ../architect/    ../coder/    ../reviewer/     clones with the submodule checked out
#
# The repo may be empty. Per-project files (AGENTS.md, CLAUDE.md, .team/) are
# scaffolded if missing, then everything is committed and pushed before the
# sibling clones are made.

set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_VERSION="$(git -C "$SKILL_DIR" describe --always --dirty 2>/dev/null || echo unversioned)"

NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "error: run this inside the po/ clone" >&2; exit 2; }
cd "$ROOT"
WS="$(dirname "$ROOT")"

# sanity: we are the po/ clone, the submodule is where we expect, origin exists
[ "$(basename "$ROOT")" = "po" ] || { echo "error: this clone must be named po/ (it is '$(basename "$ROOT")'). mv it, then rerun." >&2; exit 2; }
[ -f ".claude/skills/agent-team/SKILL.md" ] || {
  echo "error: submodule missing. Run: git submodule add <agent-team repo url> .claude/skills/agent-team" >&2; exit 2; }
URL="$(git remote get-url origin 2>/dev/null)" || { echo "error: no 'origin' remote" >&2; exit 2; }
[ -e "$WS/team" ] && { echo "error: $WS/team exists — workspace looks initialised. Use ./team add coder to grow it." >&2; exit 2; }

[ -n "$NAME" ] || NAME="$(basename "$URL" .git)"
HUMAN="$(git config --global user.name 2>/dev/null || git config user.name 2>/dev/null || echo 'the human')"

# default branch: existing repo → origin/HEAD; empty repo → main
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  DEFAULT="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  [ -n "$DEFAULT" ] || DEFAULT="$(git rev-parse --abbrev-ref HEAD)"
else
  git checkout -q -b main 2>/dev/null || true
  DEFAULT=main
fi

echo "agent-team $SKILL_VERSION — project: $NAME, human: $HUMAN, workspace: $WS"
echo
bash "$SKILL_DIR/scripts/scaffold.sh" --name "$NAME" --human "$HUMAN" --version "$SKILL_VERSION"

git config user.name "Product Owner (Opus 5)"
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git -c user.name="$HUMAN" commit -q -m "team: scaffold agent team ($SKILL_VERSION)

— agent-team skill on behalf of $HUMAN"
  git push -q -u origin "$DEFAULT"
  echo "pushed scaffold to origin/$DEFAULT"
else
  echo "nothing new to commit"
fi

# sibling clones
echo
for r in "architect|Architect (Opus 5)" "coder|Coder (Opus 5)" "reviewer|Reviewer (OpenCode GPT)"; do
  IFS='|' read -r folder author <<< "$r"
  if [ -d "$WS/$folder" ]; then echo "exists: $folder/ (left alone)"; continue; fi
  git clone -q --recurse-submodules "$URL" "$WS/$folder" 2>&1 | grep -v -e 'cloned an empty' -e 'nonexistent ref' || true
  if ! git -C "$WS/$folder" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$WS/$folder" checkout -q "$DEFAULT" && git -C "$WS/$folder" submodule update -q --init --recursive
  fi
  git -C "$WS/$folder" config user.name "$author"
  echo "cloned $folder/  (author: $author)"
done

# launcher
cp "$SKILL_DIR/workspace/team.shim" "$WS/team"
chmod +x "$WS/team"

echo
echo "workspace ready: $WS"
echo
echo "  cd $WS"
echo "  ./team open        # four windows, every role starts working"
echo "  ./team board       # the board, auto-refreshing"
echo
echo "next: fill in 'Project conventions' in po/AGENTS.md, commit, push."
