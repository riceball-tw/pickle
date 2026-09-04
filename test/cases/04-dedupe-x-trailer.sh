#!/usr/bin/env bash
# a conflict resolved by hand is recognised via its -x trailer
new_repo
echo line > c.txt; git add c.txt; git commit --quiet -m "chore: add c"; push_main
cut_release release/1.2

echo trunk > c.txt; git add c.txt; git commit --quiet -m "fix(A): trunk edit"; push_main
a=$(sha_of "fix(A)")

git switch --quiet release/1.2
echo release > c.txt; git add c.txt; git commit --quiet -m "chore: release edit"

git cherry-pick -x "$a" >/dev/null 2>&1 || true          # conflicts
echo resolved-differently > c.txt                         # a different resolution,
git add c.txt                                             # so the patch-id will not match
git cherry-pick --continue >/dev/null 2>&1
git push --quiet origin release/1.2
git switch --quiet main

msg=$(git log --format=%B -1 release/1.2)
assert_has "$msg" "cherry picked from commit" "--continue must preserve the -x trailer"

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "sync should not retry a resolved conflict"
assert_has "$OUT" "-x trailer" "the trailer is what caught it"
