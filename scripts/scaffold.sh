#!/usr/bin/env bash
# agent-team scaffold — copy .team/, AGENTS.md, CLAUDE.md into the current clone.
#
# Usage:  bash scaffold.sh [--name "Project"] [--human "Name"] [--version "vX"]
# Idempotent: never overwrites an existing file.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"

NAME=""
HUMAN=""
VERSION="unversioned"
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --human) HUMAN="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "error: not inside a git repo" >&2; exit 2; }
cd "$ROOT"
[ -n "$NAME" ] || NAME="$(basename "$ROOT")"
[ -n "$HUMAN" ] || HUMAN="$(git config user.name 2>/dev/null || echo 'the human')"

created=(); skipped=()

copy_tpl() {
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then skipped+=("$dst"); return; fi
  mkdir -p "$(dirname "$dst")"
  sed -e "s|{{PROJECT_NAME}}|$NAME|g" -e "s|{{HUMAN}}|$HUMAN|g" -e "s|{{SKILL_VERSION}}|$VERSION|g" "$src" > "$dst"
  created+=("$dst")
}

copy_tpl "$ASSETS/root/AGENTS.md" "AGENTS.md"
copy_tpl "$ASSETS/root/CLAUDE.md" "CLAUDE.md"

while IFS= read -r -d '' f; do
  copy_tpl "$f" ".team/${f#"$ASSETS"/team/}"
done < <(find "$ASSETS/team" -type f -print0)

chmod +x .team/bin/* 2>/dev/null || true

if [ ${#created[@]} -gt 0 ]; then
  echo "created:"; printf '  %s\n' "${created[@]}"
fi
if [ ${#skipped[@]} -gt 0 ]; then
  echo "left untouched:"; printf '  %s\n' "${skipped[@]}"
  for s in "${skipped[@]}"; do
    case "$s" in
      AGENTS.md) echo "  -> AGENTS.md existed. Append the team section from $ASSETS/root/AGENTS.md" ;;
      CLAUDE.md) echo "  -> CLAUDE.md existed. Make sure it says: read AGENTS.md first." ;;
    esac
  done
fi
