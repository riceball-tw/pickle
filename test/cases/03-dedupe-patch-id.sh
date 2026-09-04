#!/usr/bin/env bash
# a hand cherry-pick made without -x is still recognised
new_repo
cut_release release/1.2
cm "fix(A): alpha"
cm "fix(B): beta"
push_main
a=$(sha_of "fix(A)")

git switch --quiet release/1.2
# Diverge first: cherry-picking straight onto the branch point would reproduce a
# byte-identical commit object, so there would be nothing for patch-id to catch.
cm "chore: release marker"
git cherry-pick "$a" >/dev/null 2>&1      # deliberately no -x
[[ $(git rev-parse HEAD) != "$a" ]] || _fail "fixture did not actually copy the commit"
git push --quiet origin release/1.2
git switch --quiet main

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "sync should succeed"
assert_has "$OUT" "already present (patch-id)" "patch-id recognised the hand pick"

n=$(git log --format=%s release/1.2 | grep -cxF "fix(A): alpha")
assert_eq 1 "$n" "alpha must not be duplicated"
assert_on release/1.2 "fix(B): beta" "beta still landed"
