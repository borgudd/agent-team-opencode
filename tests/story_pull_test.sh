#!/usr/bin/env bash
# Exercises `bin/story pull` against a throwaway git "origin" plus a `gh` shim
# answering `issue list` / `issue view --json comments` (and the `pr list` /
# `run list` calls bin/status makes internally, since PULL now consults the
# board before writing a mirror status). No docker, no real network.
#
# Story 067: the GitHub sync must not be able to move a story backwards.
#   - an issue closed on GitHub for a story whose PR is already merged
#     (board status `done`) is left alone -- not overwritten to `closed`.
#   - an issue closed on GitHub for a story that is NOT done still gets
#     `status: closed` written, same as today.
#   - a comment with no body, or no known author, produces no note.
#   - a real comment produces exactly one note; pulling again appends nothing
#     (the dedup marker must actually match what got written).
#   - the 2026-09-14 shape (several closed-issue-on-done stories, several
#     null comments, all in one pull) leaves every one of them untouched.
#
# Run with: bash tests/story_pull_test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
fail=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/shim" "$WORK/comments"
cat > "$WORK/shim/gh" <<'SHIM'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then exit 0; fi
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  if [ -n "${GH_SHIM_PRS:-}" ] && [ -f "$GH_SHIM_PRS" ]; then cat "$GH_SHIM_PRS"; else echo ""; fi
  exit 0
fi
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  echo ""
  exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "list" ]; then
  if [ -n "${GH_SHIM_ISSUES:-}" ] && [ -f "$GH_SHIM_ISSUES" ]; then cat "$GH_SHIM_ISSUES"; else echo ""; fi
  exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  num="$3"
  f="${GH_SHIM_COMMENTS_DIR:-}/$num"
  if [ -f "$f" ]; then cat "$f"; else echo ""; fi
  exit 0
fi
echo "gh shim: unhandled invocation: $*" >&2
exit 1
SHIM
chmod +x "$WORK/shim/gh"
export PATH="$WORK/shim:$PATH"
export GH_SHIM_COMMENTS_DIR="$WORK/comments"

bare="$WORK/origin.git"
git init -q --bare "$bare"
work="$WORK/work"
git clone -q "$bare" "$work" 2>/dev/null
cd "$work" || exit 1
git config user.email test@example.com
git config user.name "Story Pull Test"
git checkout -q -b main 2>/dev/null || git checkout -q main

mkdir -p .team/backlog

add_story() {  # id slug title issue_number
  cat > ".team/backlog/$1-$2.md" <<EOF
---
id: $1
title: $3
issue: $4
---
Fixture story.
EOF
}

# 094/098: PR merged (board says done) but GitHub issue closed anyway -- must
# be left alone, not overwritten to status: closed (the 2026-09-14 shape).
add_story 094 done-closed-a "Fixture: done story, closed issue A" 940
add_story 098 done-closed-b "Fixture: done story, closed issue B" 941
# 095: no PR at all (board says ready, not done) + closed issue -- ordinary
# case, still gets status: closed.
add_story 095 open-closed "Fixture: open story, closed issue" 942
# 096/099: open issue, last comment has no body / no author -- no note.
add_story 096 null-comment-a "Fixture: null comment A" 943
add_story 099 null-comment-b "Fixture: null comment B" 944
# 097: open issue, a real last comment -- one note, then dedup on a second pull.
add_story 097 real-comment "Fixture: real comment" 945

git add .team
git commit -q -m "fixture stories"
git push -q origin main
git remote set-head origin -a >/dev/null 2>&1

ISSUES_FILE="$WORK/issues.tsv"
cat > "$ISSUES_FILE" <<EOF
940	094 · Fixture: done story, closed issue A	CLOSED
941	098 · Fixture: done story, closed issue B	CLOSED
942	095 · Fixture: open story, closed issue	CLOSED
943	096 · Fixture: null comment A	OPEN
944	099 · Fixture: null comment B	OPEN
945	097 · Fixture: real comment	OPEN
EOF
export GH_SHIM_ISSUES="$ISSUES_FILE"

# 940/941: comments irrelevant (empty) -- only the closed-issue-on-done path matters.
: > "$WORK/comments/940"
: > "$WORK/comments/941"
: > "$WORK/comments/942"
# 943/944: a comment exists but fails the select (no body / no author) --
# real `gh --jq 'select(...)'` prints nothing for these, same as empty.
: > "$WORK/comments/943"
: > "$WORK/comments/944"
# 945: a real comment with a body and a known author.
printf '2026-09-01T00:00:00Z alice Please double check the numbers.\n' > "$WORK/comments/945"

PRS_FILE="$WORK/prs.tsv"
cat > "$PRS_FILE" <<EOF
feat/094-done-closed-a	880	MERGED	1
feat/098-done-closed-b	881	MERGED	1
EOF
export GH_SHIM_PRS="$PRS_FILE"

STORY_BIN="$ROOT/bin/story"
out1="$("$STORY_BIN" pull 2>&1)"
rc1=$?

check_file_unchanged() {  # id label
  local id="$1" label="$2" path
  path="$(git ls-tree -r --name-only origin/main -- .team/backlog/ | grep "/${id}-")"
  if git show "origin/main:$path" | grep -q '^status:'; then
    echo "FAIL: $label ($id) got a status: line written, want none"; fail=1
  fi
}

check_status_closed() {  # id
  local id="$1" path
  path="$(git ls-tree -r --name-only origin/main -- .team/backlog/ | grep "/${id}-")"
  if ! git show "origin/main:$path" | grep -q '^status: closed$'; then
    echo "FAIL: story $id did not get status: closed written"; fail=1
  fi
}

check_no_note() {  # id
  local id="$1"
  if git ls-tree -r --name-only origin/main -- .team/notes/ | grep -q "/${id}-"; then
    echo "FAIL: story $id got a note written from an empty/authorless comment"; fail=1
  fi
}

check_note_has_marker() {  # id issue_number
  local id="$1" n="$2" note
  note="$(git ls-tree -r --name-only origin/main -- .team/notes/ | grep "/${id}-")"
  if [ -z "$note" ]; then
    echo "FAIL: story $id has no note from a real comment"; fail=1; return
  fi
  if ! git show "origin/main:$note" | grep -qF "gh:$n"; then
    echo "FAIL: story $id note has no gh:$n dedup marker"; fail=1
  fi
}

[ "$rc1" -eq 0 ] || { echo "FAIL: bin/story pull exited $rc1"; echo "$out1"; fail=1; }

# 1. done + closed issue -> left alone, and pull says so.
check_file_unchanged 094 "done story A"
check_file_unchanged 098 "done story B"
if ! printf '%s\n' "$out1" | grep -qF "pull: #940 is closed on GitHub because 094 is done — left alone"; then
  echo "FAIL: pull did not print the left-alone message for 094"; fail=1
fi

# 2. open (not done) + closed issue -> status: closed, unchanged behavior.
check_status_closed 095

# 3. empty/authorless comment -> no note at all.
check_no_note 096
check_no_note 099

# 4. a real comment -> exactly one note, carrying the dedup marker.
check_note_has_marker 097 945
note097_after_first="$(git show "origin/main:$(git ls-tree -r --name-only origin/main -- .team/notes/ | grep '/097-')" 2>/dev/null)"

# Second pull: nothing here should have changed, so the note must not gain a
# second copy of the same comment (the marker bug this story fixes).
out2="$("$STORY_BIN" pull 2>&1)"
note097_after_second="$(git show "origin/main:$(git ls-tree -r --name-only origin/main -- .team/notes/ | grep '/097-')" 2>/dev/null)"
if [ "$note097_after_first" != "$note097_after_second" ]; then
  echo "FAIL: a second pull appended the same comment again to 097's note"
  echo "--- after first pull ---"; printf '%s\n' "$note097_after_first"
  echo "--- after second pull ---"; printf '%s\n' "$note097_after_second"
  fail=1
fi
# And the still-closed-because-done and still-null-comment stories must stay
# exactly as they were, second time around too (the bulk 2026-09-14 shape).
check_file_unchanged 094 "done story A (2nd pull)"
check_file_unchanged 098 "done story B (2nd pull)"
check_no_note 096
check_no_note 099

if [ "$fail" -eq 0 ]; then
  echo "ok — story_pull_test.sh: 6/6 checks (done+closed left alone x2; open+closed -> status:closed; null-comment x2 -> no note; real comment -> one note, dedup on re-pull)"
else
  echo "--- story_pull_test.sh failures above; pull output for debugging ---"
  echo "--- first pull ---"; printf '%s\n' "$out1"
  echo "--- second pull ---"; printf '%s\n' "$out2"
fi

exit "$fail"
