#!/usr/bin/env bash
# Regression harness for bin/status. No dependencies beyond bash/git (floor:
# bash 3.2) -- this is the first test this repo has, so it stays a plain
# script rather than pulling in a framework.
#
# Builds a throwaway git repo with a bare "origin" remote, writes
# .team/backlog/ and .team/plans/ fixtures, runs `bin/status --tsv` against
# it, and compares specific fields to expected values. Never touches the
# live board.
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REMOTE="$WORK/origin.git"
REPO="$WORK/repo"
git init -q --bare "$REMOTE"
git init -q -b main "$REPO"
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name "board_test"
git -C "$REPO" remote add origin "$REMOTE"

mkdir -p "$REPO/.team/backlog" "$REPO/.team/plans"

write_story() {  # id title [depends-on]
  local id="$1" title="$2" depends="${3:-}"
  {
    echo "---"
    echo "id: $id"
    echo "title: $title"
    [ -n "$depends" ] && echo "depends-on: $depends"
    echo "---"
    echo
    echo "## Outcome"
    echo "fixture"
  } > "$REPO/.team/backlog/${id}-fixture.md"
}

write_plan() {  # id [depends-on]
  local id="$1" depends="${2:-}"
  {
    echo "---"
    echo "id: $id"
    echo "verdict: plan"
    [ -n "$depends" ] && echo "depends-on: $depends"
    echo "---"
    echo "# Plan $id"
  } > "$REPO/.team/plans/${id}-fixture.md"
}

commit_and_push() {
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "fixtures"
  git -C "$REPO" push -q origin main
  git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

pass=0
fail=0

# field(id, output, column) -- column: 2=status 4=next 5=where (1-indexed TSV)
field() {
  local id="$1" out="$2" col="$3"
  awk -F'\t' -v id="$id" -v c="$col" '$1==id {print $c}' <<< "$out"
}

assert_eq() {  # description, actual, expected
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1"
    echo "  expected: $3"
    echo "  actual:   $2"
  fi
}

# ---- Case 1: the story's own regression -- a story and its plan both declare
# the same dependency. One blocker, listed once, not twice.
write_story "022" "Blocker still planned"
write_story "023" "Depends on 022 twice over" "022"
write_plan "022"
write_plan "023" "022"
commit_and_push

out="$(cd "$REPO" && "$HERE/bin/status" --tsv)"
assert_eq "023 is blocked" "$(field 023 "$out" 2)" "blocked"
assert_eq "023's blocker named once, not 022(planned) 022(planned)" \
  "$(field 023 "$out" 5)" "blocked by: 022(planned)"

# ---- Case 2: dep-missing declared twice (story and plan both name the same
# nonexistent ID). Named once.
write_story "024" "Depends on a story that does not exist, twice" "999"
write_plan "024" "999"
commit_and_push

out="$(cd "$REPO" && "$HERE/bin/status" --tsv)"
assert_eq "024 is dep-missing" "$(field 024 "$out" 2)" "dep-missing"
assert_eq "024's missing ID named once, not 999 999" "$(field 024 "$out" 5)" "missing: 999"

# ---- Case 3: dep-cycle, each side of the loop declared twice (story and
# plan). Each ID in the cycle label appears once.
write_story "025" "Cycle half A" "026"
write_plan "025" "026"
write_story "026" "Cycle half B" "025"
write_plan "026" "025"
commit_and_push

out="$(cd "$REPO" && "$HERE/bin/status" --tsv)"
assert_eq "025 is dep-cycle" "$(field 025 "$out" 2)" "dep-cycle"
assert_eq "025's cycle label names 026 once, not twice" "$(field 025 "$out" 5)" "cycle with: 026"
assert_eq "026 is dep-cycle" "$(field 026 "$out" 2)" "dep-cycle"
assert_eq "026's cycle label names 025 once, not twice" "$(field 026 "$out" 5)" "cycle with: 025"

# ---- Case 4: enforcement is unaffected by dedup -- a single real dependency
# still blocks exactly as it did before (AC2), same fixture as case 1 re-read.
assert_eq "023's own enforcement is untouched (still blocked, not e.g. planned)" \
  "$(field 023 "$out" 2)" "blocked"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
