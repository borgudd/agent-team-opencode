#!/usr/bin/env bash
# agent-team init — create a workspace with one clone per role.
#
# Usage:
#   bash init.sh --repo <owner/repo | git url> [--dir <workspace>] [--name "Project"]
#
# Result:
#   <workspace>/team            launcher
#   <workspace>/po/             Product Owner clone
#   <workspace>/architect/      Architect clone
#   <workspace>/coder/          Coder clone
#   <workspace>/reviewer/       Reviewer clone
#
# The repo may be empty. .team/, AGENTS.md and CLAUDE.md are scaffolded into
# po/ if missing, committed and pushed before the other clones are made.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_VERSION="$(git -C "$SKILL_DIR" describe --always --dirty 2>/dev/null || echo unversioned)"

REPO=""; DIR=""; NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --dir)  DIR="$2";  shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "error: --repo is required (owner/repo or a git url)" >&2; exit 2; }

# owner/repo → full url; anything with a scheme or a colon is used as-is
case "$REPO" in
  *://*|*@*:*|/*|.*) URL="$REPO" ;;
  *) URL="https://github.com/$REPO.git" ;;
esac
REPO_NAME="$(basename "$REPO" .git)"
[ -n "$DIR" ]  || DIR="./$REPO_NAME-team"
[ -n "$NAME" ] || NAME="$REPO_NAME"

mkdir -p "$DIR"
DIR="$(cd "$DIR" && pwd)"
cd "$DIR"

if [ -e po ]; then
  echo "error: $DIR/po already exists — workspace looks initialised. Use ./team add coder to grow it." >&2
  exit 2
fi

# roles: folder | display name for git author
roles=("po|Product Owner (Fable 5.1)" "architect|Architect (Fable 5.1)" "coder|Coder (Opus 5)" "reviewer|Reviewer (Codex)")

clone_role() {
  local folder="$1" author="$2"
  git clone -q "$URL" "$folder" 2>&1 | grep -v -e 'cloned an empty repository' -e 'remote HEAD refers to nonexistent' || true
  git -C "$folder" config user.name "$author"
  # a freshly-pushed remote may not have HEAD set yet; check out the default branch explicitly
  if [ -n "${DEFAULT:-}" ] && ! git -C "$folder" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$folder" checkout -q "$DEFAULT" 2>/dev/null || true
  fi
  echo "cloned $folder/  (author: $author)"
}

# 1. first clone, scaffold, push
IFS='|' read -r folder author <<< "${roles[0]}"
clone_role "$folder" "$author"
cd "$folder"

HUMAN="$(git config --global user.name 2>/dev/null || echo 'the human')"

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  git checkout -q -b main
  DEFAULT=main
else
  DEFAULT="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  [ -n "$DEFAULT" ] || DEFAULT="$(git rev-parse --abbrev-ref HEAD)"
fi

echo
bash "$SKILL_DIR/scripts/scaffold.sh" --name "$NAME" --human "$HUMAN" --version "$SKILL_VERSION"
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git -c user.name="$HUMAN" commit -q -m "team: scaffold agent team ($SKILL_VERSION)

— agent-team skill on behalf of $HUMAN"
  git push -q -u origin "$DEFAULT"
  echo "pushed scaffold to origin/$DEFAULT"
else
  echo "repo already scaffolded; nothing to push"
fi
cd "$DIR"

# 2. the other clones
echo
for r in "${roles[@]:1}"; do
  IFS='|' read -r folder author <<< "$r"
  clone_role "$folder" "$author"
done

# 3. launcher
sed -e "s|{{URL}}|$URL|g" -e "s|{{DEFAULT}}|$DEFAULT|g" "$SKILL_DIR/assets/workspace/team" > team
chmod +x team

echo
echo "workspace ready: $DIR"
echo
echo "  cd $DIR"
echo "  ./team po          # talk here"
echo "  ./team architect   # nudge: \"check the board\""
echo "  ./team coder       # nudge: \"check the board\""
echo "  ./team reviewer    # nudge: \"review open PRs\""
echo "  ./team status      # the board"
echo
echo "next: fill in 'Project conventions' in po/AGENTS.md, commit, push."
