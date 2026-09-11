#!/usr/bin/env bash
# Exercises bin/status and bin/wait-for against a throwaway git "origin" and a
# `gh` shim, so the PR-state outcomes from story 048 (green, ci-red, pending,
# conflicting, and a verdict-only changes-requested) are asserted without
# hitting real GitHub. The shim answers `gh pr list ... --jq <filter>` by
# piping canned PR JSON through the *real* jq with the exact filter bin/status
# passed, so the jq under test here is the one that ships in bin/status, not a
# reimplementation of it. `gh run list` (used only for main-branch `needs-fix`
# now — see 048's replan) answers an empty run list, since none of these
# fixtures exercise a red main.
#
# Run with: bash tests/board.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
fail=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- a `gh` shim, first on PATH -------------------------------------------
# Only the two calls bin/status and bin/wait-for actually make: `auth status`
# (must succeed) and `pr list ... --jq FILTER` (must answer from the fixture,
# through real jq, using whatever filter was actually passed on the command
# line — so a change to the filter in bin/status is exercised here too).
mkdir -p "$WORK/shim"
FIXTURE="$WORK/prs.json"
cat > "$WORK/shim/gh" <<'SHIM'
#!/usr/bin/env bash
set -uo pipefail
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then exit 0; fi
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  filter=""
  args=("$@")
  for i in "${!args[@]}"; do
    if [ "${args[$i]}" = "--jq" ]; then filter="${args[$((i + 1))]}"; fi
  done
  exec jq -r "$filter" "$GH_SHIM_FIXTURE"
fi
# needs-fix's one remaining `gh run list` (main-branch red) — no fixture here
# exercises a red main, so an empty run list keeps redmain unset.
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  exit 0
fi
echo "gh shim: unhandled invocation: $*" >&2
exit 1
SHIM
chmod +x "$WORK/shim/gh"
export GH_SHIM_FIXTURE="$FIXTURE"
export PATH="$WORK/shim:$PATH"

cat > "$FIXTURE" <<'JSON'
[
  {"headRefName": "feat/100-green", "number": 900, "state": "OPEN",
   "mergeable": "MERGEABLE",
   "statusCheckRollup": [{"name": "tests", "status": "COMPLETED", "conclusion": "SUCCESS"}]},
  {"headRefName": "feat/101-red", "number": 901, "state": "OPEN",
   "mergeable": "MERGEABLE",
   "statusCheckRollup": [{"name": "policy", "status": "COMPLETED", "conclusion": "FAILURE"},
                          {"name": "tests", "status": "COMPLETED", "conclusion": "SUCCESS"}]},
  {"headRefName": "feat/102-pending", "number": 902, "state": "OPEN",
   "mergeable": "UNKNOWN",
   "statusCheckRollup": [{"name": "tests", "status": "IN_PROGRESS", "conclusion": null}]},
  {"headRefName": "feat/103-conflict", "number": 903, "state": "OPEN",
   "mergeable": "CONFLICTING", "statusCheckRollup": []},
  {"headRefName": "feat/104-verdict-only", "number": 904, "state": "OPEN",
   "mergeable": "MERGEABLE",
   "statusCheckRollup": [{"name": "tests", "status": "COMPLETED", "conclusion": "SUCCESS"}]}
]
JSON

# ---- a throwaway origin + working clone, four stories, all approved -------
bare="$WORK/origin.git"
git init -q --bare "$bare"

work="$WORK/work"
git clone -q "$bare" "$work" 2>/dev/null
cd "$work" || exit 1
git config user.email test@example.com
git config user.name "Board Test"
git checkout -q -b main 2>/dev/null || git checkout -q main

mkdir -p .team/backlog .team/plans
add_story() {  # id slug title
  cat > ".team/backlog/$1-$2.md" <<EOF
---
id: $1
title: $3
---
Fixture story.
EOF
  cat > ".team/plans/$1-$2.md" <<EOF
---
id: $1
verdict: plan
---
Fixture plan.
EOF
}
add_story 100 green   "Green rollup, mergeable"
add_story 101 red     "A red check on the head commit"
add_story 102 pending "All checks still pending"
add_story 103 conflict "Conflicts with main"
add_story 104 verdict-only "A real request-changes verdict, CI green and mergeable"
git add .team
git commit -q -m "fixture stories + plans"
git push -q origin main
git remote set-head origin -a >/dev/null 2>&1

add_branch() {  # id slug verdict
  git checkout -q -b "feat/$1-$2" main
  mkdir -p .team/reviews
  cat > ".team/reviews/$1-$2.md" <<EOF
---
id: $1
verdict: ${3:-approve}
---
Fixture review.
EOF
  echo "work for $1" > "src-$1.txt"
  git add "src-$1.txt" ".team/reviews/$1-$2.md"
  git commit -q -m "team(coder): fixture work $1"
  git push -q -u origin "feat/$1-$2"
  git checkout -q main
}
add_branch 100 green
add_branch 101 red
add_branch 102 pending
add_branch 103 conflict
add_branch 104 verdict-only request-changes

STATUS_BIN="$ROOT/bin/status"
WAITFOR_BIN="$ROOT/bin/wait-for"

tsv="$("$STATUS_BIN" --tsv)"

check() {  # id expected_status where_substring_or_empty
  local id="$1" want_status="$2" want_where="${3:-}"
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
  if [ -n "$want_where" ] && [[ "$got_where" != *"$want_where"* ]]; then
    echo "FAIL: story $id where=[$got_where], want it to contain [$want_where] (row: $row)"; fail=1
  fi
}

check 100 approved
check 101 ci-fails "CI red: policy"
check 102 approved
check 103 ci-fails "conflict"
check 104 changes-requested

# wait-for coder must hand back the two ci-fails stories and the one
# verdict-only changes-requested story, in ID order, and nothing else — the
# same precedence class, per 048's replan (ci-fails is the Coder's lane now,
# not the Reviewer's).
wf_out="$("$WAITFOR_BIN" coder 1 1)"
wf_ids="$(printf '%s\n' "$wf_out" | tail -n +2 | awk '{print $1}')"
want_ids="$(printf '101\n103\n104\n')"
if [ "$wf_ids" != "$want_ids" ]; then
  echo "FAIL: wait-for coder returned ids [$wf_ids], want [101, 103, 104]"
  echo "--- full wait-for output ---"; echo "$wf_out"
  fail=1
fi

# wait-for reviewer must never see a ci-fails row — that lane moved to the
# Coder entirely; the Reviewer's is in-review alone.
rf_out="$("$WAITFOR_BIN" reviewer 1 1)"
rf_ids="$(printf '%s\n' "$rf_out" | tail -n +2 | awk '{print $1}')"
if printf '%s\n' "$rf_ids" | grep -qxE '101|103'; then
  echo "FAIL: wait-for reviewer returned a ci-fails story: [$rf_ids]"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "ok — board.sh: 5/5 status checks, wait-for handoff correct"
else
  echo "--- full status --tsv for debugging ---"
  printf '%s\n' "$tsv"
fi
exit "$fail"
