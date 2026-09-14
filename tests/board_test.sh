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

# --- Story 051: red main attributed by the merged PR, not by commit-title
# text, and to the FIRST red run in the streak -- never the latest.
#
# Four stories (070-073), each already "done" via the fallback_pr path (a
# canned MERGED PR row whose branch name is never actually pushed -- exactly
# what a real merged-and-deleted topic branch looks like to bin/status), so
# the needs-fix override has something real to land on. Five separate
# `main_runs` scenarios, each its own bin/status invocation (the shim answers
# one canned file per call), because a single run list can only test one
# streak shape at a time.

add_story 070 red-story "Fixture: red run sits directly on the story's own merge"
add_story 071 green-story "Fixture: red run sits on bookkeeping after a green story merge"
add_story 072 red-story-then-plan "Fixture: red run on a plan-doc commit, red story merge further back"
add_story 073 cancelled-streak "Fixture: a cancelled run mid-streak does not break it"
add_story 074 not-yet-completed-newest "Fixture: newest run in-progress, an older run still unresolved-red"
git add .team
git commit -q -m "story 051 fixture stories + plans"
git push -q origin main

PRS2_FILE="$WORK/prs2.tsv"
cat > "$PRS2_FILE" <<EOF
feat/070-red-story	701	MERGED	1
feat/071-green-story	711	MERGED	1
feat/072-red-story-then-plan	721	MERGED	1
feat/073-cancelled-streak	731	MERGED	1
feat/074-not-yet-completed-newest	741	MERGED	1
EOF
export GH_SHIM_PRS="$PRS2_FILE" GH_SHIM_RUNS=""

run_scenario() {  # scenario_file -> sets $scenario_tsv
  export GH_SHIM_MAIN_RUN="$1"
  scenario_tsv="$("$STATUS_BIN" --tsv)"
}

status_of() {  # tsv id -> prints status
  printf '%s\n' "$1" | awk -F'\t' -v id="$2" '$1==id {print $2}'
}

main_row_where() {  # tsv -> prints WHERE of the id=main row, or nothing
  printf '%s\n' "$1" | awk -F'\t' '$1=="main" {print $5}'
}

# A: red run directly on the story's own squash-merge commit -> that story
# needs-fix.
run_scenario_a="$WORK/main_runs_a.tsv"
cat > "$run_scenario_a" <<EOF
failure	feat(070): thing (#701)	shaA1	API tests
EOF
run_scenario "$run_scenario_a"
got="$(status_of "$scenario_tsv" 070)"
if [ "$got" != needs-fix ]; then
  echo "FAIL: scenario A: story 070 status=$got, want needs-fix"; fail=1
fi
if [ -n "$(main_row_where "$scenario_tsv")" ]; then
  echo "FAIL: scenario A: an id=main row exists but a story was blamed"; fail=1
fi

# B: red run on a bookkeeping commit, with a green story merge further back
# in the same streak -- no story is blamed (the bookkeeping commit merged no
# PR), and a standalone main/main-red row names the commit and job.
run_scenario_b="$WORK/main_runs_b.tsv"
cat > "$run_scenario_b" <<EOF
failure	team(architect): plan 999	shaB1	API tests
success	feat(071): thing (#711)	shaB2	API tests
EOF
run_scenario "$run_scenario_b"
got="$(status_of "$scenario_tsv" 071)"
if [ "$got" = needs-fix ]; then
  echo "FAIL: scenario B: story 071 wrongly blamed (status=needs-fix) for a bookkeeping commit's red run"; fail=1
fi
where="$(main_row_where "$scenario_tsv")"
case "$where" in
  shaB1*) ;;
  *) echo "FAIL: scenario B: id=main row missing or wrong (where=[$where])"; fail=1 ;;
esac

# C: newest run is on a plan-doc (bookkeeping) commit, but an older run in
# the same unbroken failure streak sits on a story's own merge -- that story
# is blamed (the FIRST red run, not the latest), and no main/main-red row.
run_scenario_c="$WORK/main_runs_c.tsv"
cat > "$run_scenario_c" <<EOF
failure	team(architect): plan 888	shaC1	API tests
failure	feat(072): thing (#721)	shaC2	API tests
success	old green baseline	shaC3	API tests
EOF
run_scenario "$run_scenario_c"
got="$(status_of "$scenario_tsv" 072)"
if [ "$got" != needs-fix ]; then
  echo "FAIL: scenario C: story 072 status=$got, want needs-fix (the first red run in the streak, not the latest)"; fail=1
fi
if [ -n "$(main_row_where "$scenario_tsv")" ]; then
  echo "FAIL: scenario C: an id=main row exists but a story (072) was blamed"; fail=1
fi

# D: the newest run is green, even though older runs in the list failed --
# main is not red at all.
run_scenario_d="$WORK/main_runs_d.tsv"
cat > "$run_scenario_d" <<EOF
success	something fine	shaD1	API tests
failure	feat(999): ignored	shaD2	API tests
EOF
run_scenario "$run_scenario_d"
if [ -n "$(main_row_where "$scenario_tsv")" ]; then
  echo "FAIL: scenario D: an id=main row exists but the newest run was green"; fail=1
fi
for id in 070 071 072 073; do
  got="$(status_of "$scenario_tsv" "$id")"
  if [ "$got" = needs-fix ]; then
    echo "FAIL: scenario D: story $id wrongly needs-fix when the newest main run is green"; fail=1
  fi
done

# E: a cancelled run in the middle of the streak neither ends it nor becomes
# the answer -- the story merge further back still gets blamed.
run_scenario_e="$WORK/main_runs_e.tsv"
cat > "$run_scenario_e" <<EOF
failure	team(architect): plan 777	shaE1	API tests
cancelled		shaE2	API tests
failure	feat(073): thing (#731)	shaE3	API tests
success	baseline	shaE4	API tests
EOF
run_scenario "$run_scenario_e"
got="$(status_of "$scenario_tsv" 073)"
if [ "$got" != needs-fix ]; then
  echo "FAIL: scenario E: story 073 status=$got, want needs-fix (a cancelled run must not break the streak)"; fail=1
fi
if [ -n "$(main_row_where "$scenario_tsv")" ]; then
  echo "FAIL: scenario E: an id=main row exists but a story (073) was blamed"; fail=1
fi

# F (review round 1): the newest run has not completed yet (empty
# conclusion -- still queued or in progress) and an older run in the same
# streak is a genuine, still-unresolved failure. An in-progress newest run is
# not proof main is green; it must not mask a real red streak underneath it.
run_scenario_f="$WORK/main_runs_f.tsv"
printf '\tin progress run\tshaF1\tAPI tests\nfailure\tfeat(074): thing (#741)\tshaF2\tAPI tests\nsuccess\tbaseline\tshaF3\tAPI tests\n' > "$run_scenario_f"
run_scenario "$run_scenario_f"
got="$(status_of "$scenario_tsv" 074)"
if [ "$got" != needs-fix ]; then
  echo "FAIL: scenario F: story 074 status=$got, want needs-fix (an in-progress newest run must not hide an older unresolved failure)"; fail=1
fi
if [ -n "$(main_row_where "$scenario_tsv")" ]; then
  echo "FAIL: scenario F: an id=main row exists but a story (074) was blamed"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "ok — board_test.sh: 6/6 story-051 red-main-attribution scenarios (A-F: direct story blame, bookkeeping-with-no-PR gets a main row, first-red-not-latest, green-newest-means-nothing-red, cancelled-mid-streak doesn't break it, in-progress-newest doesn't hide an older red)"
else
  echo "--- story-051 fixtures failed; full status --tsv for debugging ---"
  printf '%s\n' "$scenario_tsv"
fi

# --- Story 060: newer-of-review-vs-work decided by commit ancestry, not
# committer date -- a rebase rewrites every commit's committer date to the
# moment of the rebase, so a review commit and the Coder's later fix can land
# in the same epoch second. A plain `>=` timestamp tie then reads the review
# as still current even though the fix is its descendant. Four branches, all
# green CI (mergeable, no conflict, a "success" run) so the story-050 rules
# stay out of the way and only the ancestry decision is under test.

add_story 080 fix-after-review "Fixture: a Coder fix committed after the review"
add_story 081 review-after-fix "Fixture: a review committed after the Coder's fix"
add_story 082 rebase-same-second "Fixture: review and fix share a committer second (rebase)"
add_story 083 unrelated-history "Fixture: a review on unrelated history, timestamp fallback"
git add .team
git commit -q -m "story 060 fixture stories + plans"
git push -q origin main

# 080: work, then a request-changes review on top (the review is the latest
# word) -> changes-requested/coder, same shape the existing 060 fixture above
# already covers -- kept here too so the four story-060 cases read together.
git checkout -q main
mk_branch 080 fix-after-review
add_work 080 fix-after-review "080 work" "$T0"
add_review 080 fix-after-review request-changes "$((T0 + 100))"
git push -q origin feat/080-fix-after-review

# 081: a request-changes review, then a Coder fix on top (ordinary, distinct
# timestamps) -> in-review/reviewer: the fix is a descendant of the review.
git checkout -q main
mk_branch 081 review-after-fix
add_review 081 review-after-fix request-changes "$T0"
add_work 081 review-after-fix "081 fix" "$((T0 + 100))"
git push -q origin feat/081-review-after-fix

# 082: the rebase case this story exists for -- review then fix, but BOTH
# commits carry the exact same committer second (what `git rebase` does to
# every commit it replays). Timestamps alone cannot break the tie; ancestry
# still can, since the fix commit still has the review commit as a parent.
git checkout -q main
mk_branch 082 rebase-same-second
add_review 082 rebase-same-second request-changes "$T0"
add_work 082 rebase-same-second "082 fix" "$T0"
git push -q origin feat/082-rebase-same-second

# 083: a review committed on an unrelated history (no common ancestor with
# the work commit) and merged in with `--allow-unrelated-histories`, at a
# LATER timestamp than the work commit -- ancestry cannot decide either
# direction, so this falls back to the old timestamp comparison, which still
# reads the review as current -> changes-requested/coder.
git checkout -q main
mk_branch 083 unrelated-history
add_work 083 unrelated-history "083 work" "$T0"
git checkout -q --orphan orphan-083-review
git rm -rq --cached . >/dev/null 2>&1
mkdir -p .team/reviews
cat > .team/reviews/083-unrelated-history.md <<EOF
---
id: 083
verdict: request-changes
---
Fixture review on unrelated history.
EOF
git add .team/reviews/083-unrelated-history.md
GIT_COMMITTER_DATE="@$((T0 + 100))" GIT_AUTHOR_DATE="@$((T0 + 100))" git commit -q -m "orphan review 083"
git clean -q -fdx >/dev/null 2>&1
git checkout -q feat/083-unrelated-history
git merge -q --no-edit --allow-unrelated-histories orphan-083-review
git push -q origin feat/083-unrelated-history
git branch -q -D orphan-083-review

git checkout -q main

PRS3_FILE="$WORK/prs3.tsv"
cat > "$PRS3_FILE" <<EOF
feat/080-fix-after-review	801	OPEN	1
feat/081-review-after-fix	802	OPEN	1
feat/082-rebase-same-second	803	OPEN	1
feat/083-unrelated-history	804	OPEN	1
EOF

RUNS3_FILE="$WORK/runs3.tsv"
cat > "$RUNS3_FILE" <<EOF
feat/080-fix-after-review	success	2026-01-01T00:00:00Z
feat/081-review-after-fix	success	2026-01-01T00:00:00Z
feat/082-rebase-same-second	success	2026-01-01T00:00:00Z
feat/083-unrelated-history	success	2026-01-01T00:00:00Z
EOF

export GH_SHIM_PRS="$PRS3_FILE" GH_SHIM_RUNS="$RUNS3_FILE" GH_SHIM_MAIN_RUN=""
tsv3="$("$STATUS_BIN" --tsv)"

check3() {  # id expected_status expected_next
  local id="$1" want_status="$2" want_next="$3"
  local row got_status got_next
  row="$(printf '%s\n' "$tsv3" | awk -F'\t' -v id="$id" '$1==id')"
  if [ -z "$row" ]; then
    echo "FAIL: no row for story $id"; fail=1; return
  fi
  got_status="$(printf '%s' "$row" | cut -f2)"
  got_next="$(printf '%s' "$row" | cut -f4)"
  if [ "$got_status" != "$want_status" ] || [ "$got_next" != "$want_next" ]; then
    echo "FAIL: story $id status=$got_status/next=$got_next, want $want_status/$want_next (row: $row)"; fail=1
  fi
}

check3 080 changes-requested coder
check3 081 in-review reviewer
check3 082 in-review reviewer
check3 083 changes-requested coder

if [ "$fail" -eq 0 ]; then
  echo "ok — board_test.sh: 4/4 story-060 review-ancestry checks (review after fix -> coder; fix after review -> reviewer; fix after review at the same rebase second -> reviewer; unrelated histories -> timestamp fallback)"
else
  echo "--- story-060 fixtures failed; full status --tsv for debugging ---"
  printf '%s\n' "$tsv3"
fi

exit "$fail"
