#!/usr/bin/env bash
# the repo states that would break cherry-pick are caught up front
new_repo
echo shared > c.txt; git add c.txt; git commit --quiet -m "chore: add c"; push_main
cut_release release/1.2
echo trunk > c.txt; git add c.txt; git commit --quiet -m "fix(A): trunk edit"; push_main

# --- a release branch that does not exist ----------------------------------
run_pickle sync --target release/nope --from main
assert_status 3 "$STATUS" "missing release branch is a preflight failure"
assert_has "$OUT" "does not exist" "and says so"
assert_has "$OUT" "pickle cut"     "and says how to fix it"

# --- uncommitted changes ----------------------------------------------------
echo scratch >> dirty.txt
git add dirty.txt
run_pickle sync --target release/1.2 --from main
assert_status 3 "$STATUS" "a dirty tree is a preflight failure"
assert_has "$OUT" "uncommitted changes" "and says so"
git reset --quiet
rm -f dirty.txt

# --- a cherry-pick already in progress --------------------------------------
git switch --quiet release/1.2
echo release > c.txt; git add c.txt; git commit --quiet -m "chore: release edit"
a=$(sha_of "fix(A)")
git cherry-pick "$a" >/dev/null 2>&1 || true
[[ -e .git/CHERRY_PICK_HEAD ]] || _fail "fixture failed to leave a pick in progress"

run_pickle sync --target release/1.2 --from main
assert_status 3 "$STATUS" "an in-progress cherry-pick is a preflight failure"
assert_has "$OUT" "already in progress" "and says so"
assert_has "$OUT" "cherry-pick --abort" "and offers a way out"

git cherry-pick --abort
