#!/usr/bin/env bash
# a commit with nothing left to apply is skipped, not treated as a failure
new_repo
printf 'g\n' > g.txt; printf 'h\n' > h.txt
git add g.txt h.txt; git commit --quiet -m "chore: files"; push_main
cut_release release/1.2

printf 'gnew\n' >> g.txt; git add g.txt
git commit --quiet -m "fix(A): change g"
push_main

# The release branch gets the same change to g, but bundled with a change to h,
# so the patch-ids differ and pickle will actually attempt the pick.
git switch --quiet release/1.2
printf 'gnew\n' >> g.txt; printf 'hnew\n' >> h.txt
git add g.txt h.txt; git commit --quiet -m "chore: superset of the fix"
git push --quiet origin release/1.2
git switch --quiet main

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "an empty pick is not a failure"
assert_has "$OUT" "nothing left to apply" "and is reported as such"

n=$(git log --format=%s release/1.2 | grep -cxF "fix(A): change g")
assert_eq 0 "$n" "no empty commit was created"
git diff --quiet || _fail "left the working tree dirty"
