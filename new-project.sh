#!/usr/bin/env bash
# agent-team new-project — everything from "I want a project" to a running workspace.
#
#   curl -sL https://raw.githubusercontent.com/fltman/agent-team/main/new-project.sh | bash -s -- <name>
#   # or, from a clone of agent-team:
#   ~/Projekt/agent-team/new-project.sh <name>
#
# Usage: new-project.sh <name | owner/name> [--public|--private] [--dir DIR]
#                       [--team-url URL] [--team-version TAG] [--no-open]
#
#   <name>          GitHub repo. Created if it does not exist (private by default).
#   --dir DIR       workspace directory (default: ./<name>-team)
#   --team-url      the agent-team repo to pin (default: the clone this script runs from,
#                   else https://github.com/fltman/agent-team.git)
#   --team-version  tag to pin (default: newest tag on the team repo)
#   --no-open       do not open the four role windows at the end
#
# Result: DIR/team launcher, DIR/po/ (with the submodule), DIR/architect/, DIR/coder/, DIR/reviewer/

set -euo pipefail

NAME=""; VIS="--private"; DIR=""; TEAM_URL=""; TEAM_VERSION=""; OPEN=yes
while [ $# -gt 0 ]; do
  case "$1" in
    --public|--private) VIS="$1"; shift ;;
    --dir) DIR="$2"; shift 2 ;;
    --team-url) TEAM_URL="$2"; shift 2 ;;
    --team-version) TEAM_VERSION="$2"; shift 2 ;;
    --no-open) OPEN=no; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) NAME="$1"; shift ;;
  esac
done
[ -n "$NAME" ] || { echo "usage: new-project.sh <name | owner/name> [--public|--private] [--dir DIR]" >&2; exit 2; }

for t in git gh; do command -v "$t" >/dev/null || { echo "error: $t not found" >&2; exit 2; }; done
gh auth status >/dev/null 2>&1 || { echo "error: gh is not logged in (gh auth login)" >&2; exit 2; }

# owner/name
case "$NAME" in
  */*) OWNER="${NAME%%/*}"; NAME="${NAME##*/}" ;;
  *)   OWNER="$(gh api user -q .login)" ;;
esac
REPO="$OWNER/$NAME"
[ -n "$DIR" ] || DIR="./$NAME-team"

# team repo: the clone this script lives in, if any
if [ -z "$TEAM_URL" ]; then
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [ -n "$self_dir" ] && [ -f "$self_dir/SKILL.md" ]; then
    TEAM_URL="$(git -C "$self_dir" remote get-url origin 2>/dev/null || true)"
  fi
fi
[ -n "$TEAM_URL" ] || TEAM_URL="https://github.com/fltman/agent-team.git"

if [ -z "$TEAM_VERSION" ]; then
  TEAM_VERSION="$(git ls-remote --tags --refs "$TEAM_URL" 2>/dev/null | sed 's|.*refs/tags/||' | sort -V | tail -1 || true)"
fi

echo "project:  $REPO ($VIS)"
echo "team:     $TEAM_URL @ ${TEAM_VERSION:-main}"
echo "workdir:  $DIR"
echo

# 1. repo
if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "repo exists: $REPO"
else
  gh repo create "$REPO" "$VIS" >/dev/null
  echo "created:     https://github.com/$REPO"
fi

# 2. workspace + po/
[ -e "$DIR/po" ] && { echo "error: $DIR/po already exists" >&2; exit 2; }
mkdir -p "$DIR"
WS="$(cd "$DIR" && pwd)"
git clone -q "https://github.com/$REPO.git" "$DIR/po" 2>&1 | grep -v 'cloned an empty' || true
cd "$DIR/po"

# 3. pin the team
git submodule add -q "$TEAM_URL" .claude/skills/agent-team
if [ -n "$TEAM_VERSION" ]; then
  git -C .claude/skills/agent-team checkout -q "$TEAM_VERSION"
  git add .claude/skills/agent-team
fi
echo "pinned:      agent-team $(git -C .claude/skills/agent-team describe --always)"
echo

# 4. scaffold, push, sibling clones, launcher
bash .claude/skills/agent-team/scripts/init.sh --name "$NAME"

# 5. open the four role windows (macOS Terminal 2×2, or tmux elsewhere)
if [ "$OPEN" = yes ] && [ -t 1 ]; then
  echo
  "$WS/team" open
fi
