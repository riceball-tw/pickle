#!/usr/bin/env bash
# any git log invocation is a selection rule, and order is corrected
new_repo
cut_release release/1.2

cm "chore: URGENT first"
cm "unrelated work"
cm "chore: URGENT second"
push_main

set +e
OUT=$(git log --format=%H --grep=URGENT main | "$PICKLE" pick --target release/1.2 --from main - 2>&1)
STATUS=$?
set -e

assert_status 0 "$STATUS" "pick from stdin"
assert_on     release/1.2 "chore: URGENT first"  "first landed"
assert_on     release/1.2 "chore: URGENT second" "second landed"
assert_not_on release/1.2 "unrelated work"       "nothing else came along"

# git log prints newest first; pickle must still apply oldest first
order=$(git log --format=%s --reverse release/1.2 | grep URGENT | tr '\n' '|')
assert_eq "chore: URGENT first|chore: URGENT second|" "$order" "stdin order corrected"

# pick ignores the type filter: these are chore commits
assert_lacks "$OUT" "type not selected" "explicit picks bypass the subject filter"
