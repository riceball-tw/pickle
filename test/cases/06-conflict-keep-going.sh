#!/usr/bin/env bash
# --keep-going skips the conflict and lands the rest
new_repo
echo base > c.txt; git add c.txt; git commit --quiet -m "chore: add c"; push_main
cut_release release/1.2

git switch --quiet release/1.2
echo release-side > c.txt; git add c.txt; git commit --quiet -m "chore: release tweak"
git push --quiet origin release/1.2
git switch --quiet main

cm "fix(A): clean one" a.txt
echo trunk-side > c.txt; git add c.txt; git commit --quiet -m "fix(B): conflicting"
cm "fix(C): clean two" b.txt
push_main

run_pickle sync --target release/1.2 --from main --keep-going
assert_status 1 "$STATUS" "still fails: a commit needs a human"

assert_on     release/1.2 "fix(A): clean one"   "first clean pick landed"
assert_on     release/1.2 "fix(C): clean two"   "the pick after the conflict landed too"
assert_not_on release/1.2 "fix(B): conflicting" "the conflicting commit did not"

assert_lacks "$OUT" "not attempted" "nothing is left unattempted with --keep-going"
git diff --quiet || _fail "left the working tree dirty"
