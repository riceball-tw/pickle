#!/usr/bin/env bash
# sync puts you back on the branch you started on, and refuses a self-pick
new_repo
cut_release release/1.2
cm "fix(A): one"
push_main

git switch --quiet -c my/work main
run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "sync from an unrelated branch"
assert_eq "my/work" "$(git symbolic-ref --short HEAD)" "you end up where you started"
assert_on release/1.2 "fix(A): one" "and the pick still landed"

# and it still works when you were already standing on the release branch
git switch --quiet main
cm "fix(C): three"
push_main
git switch --quiet release/1.2
run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "sync while standing on the release branch"
assert_eq "release/1.2" "$(git symbolic-ref --short HEAD)" "still on the release branch"

# picking a branch onto itself is a usage error, not a silent no-op
run_pickle sync --target main --from main
assert_status 2 "$STATUS" "target == from is a usage error"
assert_has "$OUT" "same branch" "and says so"
