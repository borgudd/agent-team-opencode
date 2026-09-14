#!/usr/bin/env bash
# Exercises bin/status against a throwaway git "origin" — no docker, no gh
# calls (a `gh` shim on PATH answers `auth status` success and `pr list`/`run
# list` empty, since none of these fixtures need PR or CI state). This is the
# first test this repo has: plain shell, bash 3.2 compatible, no dependencies
# beyond git and the awk/sed already required to run bin/status itself.
#
# Story 042: a dependency declared in both a story and its plan must be
# listed once, not concatenated. Run with: bash tests/board_test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
fail=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/shim"
cat > "$WORK/shim/gh" <<'SHIM'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then exit 0; fi
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then echo ""; exit 0; fi
if [ "$1" = "run" ] && [ "$2" = "list" ]; then echo ""; exit 0; fi
echo "gh shim: unhandled invocation: $*" >&2
exit 1
SHIM
chmod +x "$WORK/shim/gh"
export PATH="$WORK/shim:$PATH"

bare="$WORK/origin.git"
git init -q --bare "$bare"
work="$WORK/work"
git clone -q "$bare" "$work" 2>/dev/null
cd "$work" || exit 1
git config user.email test@example.com
git config user.name "Board Test"
git checkout -q -b main 2>/dev/null || git checkout -q main

mkdir -p .team/backlog .team/plans
add_story() {  # id slug title [depends-on]
  cat > ".team/backlog/$1-$2.md" <<EOF
---
id: $1
title: $3
${4:+depends-on: $4}
---
Fixture story.
EOF
  cat > ".team/plans/$1-$2.md" <<EOF
---
id: $1
verdict: plan
${4:+depends-on: $4}
---
Fixture plan.
EOF
}

# Two ordinary, unplanned dependencies for 023/024 to point at.
add_story 021 dep "A dependency story"
add_story 022 dep "Another dependency story"

# 023: depends-on: 022, declared in both story and plan (the story's own
# example) -- must render "blocked by: 022(ready)" once, not twice.
add_story 023 dup "One failed portfolio run sends one alert" 022

# 024: depends-on: 021, 022, declared in both -- each ID once, in order.
add_story 024 dup "The claim races are proven against a real db" "021, 022"

# 025: depends-on: 999 (nonexistent), declared in both -- dep-missing's
# "missing:" label must also name it once (AC4).
add_story 025 missing-dup "Depends on the same missing ID twice" 999

# 026/027: mutual depends-on, declared in both story and plan on each side --
# dep-cycle's "cycle with:" label must also name each ID once (AC4).
add_story 026 cycle-dup "First half of a duplicated cycle" 027
add_story 027 cycle-dup "Second half of a duplicated cycle" 026

git add .team
git commit -q -m "fixture stories + plans"
git push -q origin main
git remote set-head origin -a >/dev/null 2>&1

STATUS_BIN="$ROOT/bin/status"
tsv="$("$STATUS_BIN" --tsv)"

check() {  # id expected_status where_substring
  local id="$1" want_status="$2" want_where="$3"
  local row
  row="$(printf '%s\n' "$tsv" | awk -F'\t' -v id="$id" '$1==id')"
  if [ -z "$row" ]; then
    echo "FAIL: no row for story $id"; fail=1; return
  fi
  local got_status got_where
  got_status="$(printf '%s' "$row" | cut -f2)"
  got_where="$(printf '%s' "$row" | cut -f5)"
  if [ "$got_status" != "$want_status" ]; then
    echo "FAIL: story $id status=$got_status, want $want_status (row: $row)"; fail=1
  fi
  if [ -n "$want_where" ] && [ "$got_where" != "$want_where" ]; then
    echo "FAIL: story $id where=[$got_where], want exactly [$want_where] (row: $row)"; fail=1
  fi
}

check 023 blocked "blocked by: 022(planned)"
check 024 blocked "blocked by: 021(planned) 022(planned)"
check 025 dep-missing "missing: 999"
check 026 dep-cycle "cycle with: 027"
check 027 dep-cycle "cycle with: 026"

if [ "$fail" -eq 0 ]; then
  echo "ok — board_test.sh: 5/5 dedup checks (blocked/dep-missing/dep-cycle each name an ID once)"
else
  echo "--- full status --tsv for debugging ---"
  printf '%s\n' "$tsv"
fi
exit "$fail"
