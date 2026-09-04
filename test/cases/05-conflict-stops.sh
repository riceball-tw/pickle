#!/usr/bin/env bash
# a conflict stops the run, keeps earlier picks, leaves the tree clean
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

run_pickle sync --target release/1.2 --from main
assert_status 1 "$STATUS" "a conflict must fail the build"

assert_on     release/1.2 "fix(A): clean one"  "the clean pick before the conflict landed"
assert_not_on release/1.2 "fix(B): conflicting" "the conflicting commit must not land"
assert_not_on release/1.2 "fix(C): clean two"  "commits after the conflict are not attempted"

assert_has "$OUT" "CONFLICT"      "the conflict is reported"
assert_has "$OUT" "not attempted" "and so is what it blocked"
assert_has "$OUT" "cherry-pick -x" "with copy-paste recovery including -x"

[[ -e .git/CHERRY_PICK_HEAD ]] && _fail "left a cherry-pick in progress"
git diff --quiet || _fail "left the working tree dirty"
git diff --cached --quiet || _fail "left changes staged"

git fetch --quiet origin
assert_on origin/release/1.2 "fix(A): clean one" "the clean pick was still pushed"
