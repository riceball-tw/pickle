#!/usr/bin/env bash
# --first-parent picks merge commits, and patch-id still dedupes them
new_repo
cut_release release/pick
cut_release release/dedupe

git switch --quiet -c feat/x main
cm "wip: part one"
cm "wip: part two"
git switch --quiet main
git merge --quiet --no-ff -m "fix(DS-1): merged hotfix" feat/x

git switch --quiet -c feat/y main
cm "wip: unrelated"
git switch --quiet main
git merge --quiet --no-ff -m "feat(DS-2): merged feature" feat/y
push_main

# --- the merge is picked whole, with -m 1 -----------------------------------
run_pickle sync --target release/pick --from main --first-parent
assert_status 0 "$STATUS" "sync over a merge-commit trunk"
assert_on     release/pick "fix(DS-1): merged hotfix"   "the fix merge was picked"
assert_not_on release/pick "feat(DS-2): merged feature" "the feature merge was not"
assert_not_on release/pick "wip: part one"              "its constituent commits do not appear separately"

files=$(git ls-tree --name-only -r release/pick | tr '\n' '|')
assert_has "$files" "fwip--part-one.txt" "the merge brought its first commit's content"
assert_has "$files" "fwip--part-two.txt" "and its second"

# --- and a hand pick of a merge, made without -x, is recognised -------------
git switch --quiet release/dedupe
cm "chore: diverge"
merge_sha=$(git log --format=%H --grep="fix(DS-1)" -1 main)
git cherry-pick -m 1 "$merge_sha" >/dev/null 2>&1
git push --quiet origin release/dedupe
git switch --quiet main

msg=$(git log --format=%B -1 release/dedupe)
assert_lacks "$msg" "cherry picked from commit" "fixture must not leave an -x trailer"

run_pickle sync --target release/dedupe --from main --first-parent
assert_status 0 "$STATUS" "sync after a hand pick of a merge"
assert_has "$OUT" "already present (patch-id)" "patch-id must catch a merge, not just the trailer"
