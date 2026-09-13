#!/usr/bin/env bash
# Exercises bin/status against a throwaway git "origin" — no docker, no gh
# calls (a `gh` shim on PATH answers `auth status` success and `pr list`/`run
# list`, either empty or from canned TSV files two env vars point at, since
# none of the dedup fixtures below need PR or CI state but the CONFLICTING/
# red-PR fixtures further down do). Plain shell, bash 3.2 compatible, no
# dependencies beyond git and the awk/sed already required to run bin/status
# itself.
#
# Story 042: a dependency declared in both a story and its plan must be
# listed once, not concatenated.
# Story 050: a CONFLICTING PR, or a red/stalled PR the Reviewer has already
# sent back with request-changes, reaches the Coder rather than sitting
# invisible or bouncing to the Reviewer again.
# Run with: bash tests/board_test.sh
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
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  if [ -n "${GH_SHIM_PRS:-}" ] && [ -f "$GH_SHIM_PRS" ]; then cat "$GH_SHIM_PRS"; else echo ""; fi
  exit 0
fi
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  # bin/status makes two different `run list` calls: one with --branch (the
  # single newest run on main, for needs-fix) and one without (every
  # PR-event run, for ci-fails/stalled) -- canned separately so a fixture
  # can be red on its own PR without also faking a red main.
  branch_arg=""
  prev=""
  for a in "$@"; do
    [ "$prev" = "--branch" ] && branch_arg="$a"
    prev="$a"
  done
  if [ -n "$branch_arg" ]; then
    if [ -n "${GH_SHIM_MAIN_RUN:-}" ] && [ -f "$GH_SHIM_MAIN_RUN" ]; then cat "$GH_SHIM_MAIN_RUN"; else echo ""; fi
  else
    if [ -n "${GH_SHIM_RUNS:-}" ] && [ -f "$GH_SHIM_RUNS" ]; then cat "$GH_SHIM_RUNS"; else echo ""; fi
  fi
  exit 0
fi
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
  echo "--- dedup fixtures failed; full status --tsv for debugging ---"
  printf '%s\n' "$tsv"
fi

# --- Story 050: CONFLICTING and red/stalled-PR routing ---------------------
#
# Five fixture branches, one PR each (numbered 601-605), one review each
# (except 063, deliberately reviewless) -- pushed to the same throwaway
# origin. `gh pr list`/`gh run list` are answered from canned TSV files the
# shim above reads, shaped exactly like the real `--jq` output.

add_review() {  # id slug verdict committer_date(epoch seconds)
  local id="$1" slug="$2" verdict="$3" at="$4"
  mkdir -p .team/reviews
  cat > ".team/reviews/$id-$slug.md" <<EOF
---
id: $id
verdict: $verdict
---
Fixture review.
EOF
  git add ".team/reviews/$id-$slug.md"
  GIT_COMMITTER_DATE="@$at" GIT_AUTHOR_DATE="@$at" git commit -q -m "review $id"
}

add_work() {  # id slug marker committer_date(epoch seconds)
  local id="$1" slug="$2" marker="$3" at="$4"
  echo "$marker" > ".team/work-$id-$slug.txt"
  git add ".team/work-$id-$slug.txt"
  GIT_COMMITTER_DATE="@$at" GIT_AUTHOR_DATE="@$at" git commit -q -m "work $id"
}

mk_branch() {  # id slug -> branch name on stdout; checks out from main
  local id="$1" slug="$2"
  git checkout -q -b "feat/$id-$slug" main
}

T0=1700000000  # arbitrary fixed epoch second; only relative ordering matters

add_story 060 red-review "Fixture: red CI, current request-changes review"
add_story 061 red-approved "Fixture: red CI, approve review"
add_story 062 conflict-approved "Fixture: CONFLICTING, approve review, green CI"
add_story 063 red-no-review "Fixture: red CI, no review"
add_story 064 stale-review-red "Fixture: red CI, stale request-changes review"
git add .team
git commit -q -m "story 050 fixture stories + plans"
git push -q origin main

# 060: red run + a request-changes review newer than the last work commit ->
# stays changes-requested/coder, WHERE names the CI reason (rule 2).
mk_branch 060 red-review
add_work 060 red-review "060 work" "$T0"
add_review 060 red-review request-changes "$((T0 + 100))"
git push -q origin feat/060-red-review

# 061: red run + an approve review -> ci-fails/reviewer, unchanged from today
# (rule 3 -- CI still gates an approved PR).
git checkout -q main
mk_branch 061 red-approved
add_work 061 red-approved "061 work" "$T0"
add_review 061 red-approved approve "$((T0 + 100))"
git push -q origin feat/061-red-approved

# 062: CONFLICTING against main + an approve review, CI green -- proves rule
# 1 (CONFLICTING wins over everything, including an approve) independently of
# any red/stalled signal.
git checkout -q main
mk_branch 062 conflict-approved
add_work 062 conflict-approved "062 work" "$T0"
add_review 062 conflict-approved approve "$((T0 + 100))"
git push -q origin feat/062-conflict-approved

# 063: red run, no review at all -> ci-fails/reviewer (unchanged).
git checkout -q main
mk_branch 063 red-no-review
add_work 063 red-no-review "063 work" "$T0"
git push -q origin feat/063-red-no-review

# 064: a request-changes review, then a further work commit newer than it
# (a stale review) + red run -> ci-fails/reviewer -- the Reviewer's job is
# unchanged when their own review is stale (AC3's other half).
git checkout -q main
mk_branch 064 stale-review-red
add_review 064 stale-review-red request-changes "$T0"
add_work 064 stale-review-red "064 later work" "$((T0 + 100))"
git push -q origin feat/064-stale-review-red

git checkout -q main

PRS_FILE="$WORK/prs.tsv"
cat > "$PRS_FILE" <<EOF
feat/060-red-review	601	OPEN	1
feat/061-red-approved	602	OPEN	1
feat/062-conflict-approved	603	OPEN	1	1
feat/063-red-no-review	604	OPEN	1
feat/064-stale-review-red	605	OPEN	1
EOF

RUNS_FILE="$WORK/runs.tsv"
cat > "$RUNS_FILE" <<EOF
feat/060-red-review	failure	2026-01-01T00:00:00Z
feat/061-red-approved	failure	2026-01-01T00:00:00Z
feat/062-conflict-approved	success	2026-01-01T00:00:00Z
feat/063-red-no-review	failure	2026-01-01T00:00:00Z
feat/064-stale-review-red	failure	2026-01-01T00:00:00Z
EOF

export GH_SHIM_PRS="$PRS_FILE" GH_SHIM_RUNS="$RUNS_FILE" GH_SHIM_MAIN_RUN=""

tsv2="$("$STATUS_BIN" --tsv)"

check2() {  # id expected_status expected_next where_exact
  local id="$1" want_status="$2" want_next="$3" want_where="$4"
  local row
  row="$(printf '%s\n' "$tsv2" | awk -F'\t' -v id="$id" '$1==id')"
  if [ -z "$row" ]; then
    echo "FAIL: no row for story $id"; fail=1; return
  fi
  local got_status got_next got_where
  got_status="$(printf '%s' "$row" | cut -f2)"
  got_next="$(printf '%s' "$row" | cut -f4)"
  got_where="$(printf '%s' "$row" | cut -f5)"
  if [ "$got_status" != "$want_status" ]; then
    echo "FAIL: story $id status=$got_status, want $want_status (row: $row)"; fail=1
  fi
  if [ "$got_next" != "$want_next" ]; then
    echo "FAIL: story $id next=$got_next, want $want_next (row: $row)"; fail=1
  fi
  if [ "$got_where" != "$want_where" ]; then
    echo "FAIL: story $id where=[$got_where], want exactly [$want_where] (row: $row)"; fail=1
  fi
}

check2 060 changes-requested coder "#601 (CI red)"
check2 061 ci-fails reviewer "#602 (CI red)"
check2 062 changes-requested coder "#603 (conflict)"
check2 063 ci-fails reviewer "#604 (CI red)"
check2 064 ci-fails reviewer "#605 (CI red)"

if [ "$fail" -eq 0 ]; then
  echo "ok — board_test.sh: 5/5 story-050 routing checks (conflict beats everything; a current request-changes review beats a red-CI bounce to the reviewer; approve/no-review/stale-review still gate on CI)"
else
  echo "--- story-050 fixtures failed; full status --tsv for debugging ---"
  printf '%s\n' "$tsv2"
fi

# --- wait-for coder must offer both send-back rows in the changes-requested
# class (AC4 -- proven by a test, not by code: wait-for's own class_rank
# already ranks coder:changes-requested at 1, so this only has to show the
# rows actually reach it).
WAIT_BIN="$ROOT/bin/wait-for"
wait_out="$(cd "$work" && "$WAIT_BIN" coder 0 0 2>&1)"
wait_status=$?
if [ "$wait_status" -ne 0 ]; then
  echo "FAIL: wait-for coder exited $wait_status, want 0 (output: $wait_out)"; fail=1
else
  for id in 060 062; do
    case "$wait_out" in
      *"$id"*) ;;
      *) echo "FAIL: wait-for coder output missing story $id (output: $wait_out)"; fail=1 ;;
    esac
  done
  if [ "$fail" -eq 0 ]; then
    echo "ok — board_test.sh: wait-for coder lists both send-back rows (060, 062) in its changes-requested class"
  fi
fi

exit "$fail"
