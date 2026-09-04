#!/usr/bin/env bash
# a depth-1 CI checkout is deepened rather than failing
new_repo
cut_release release/1.2
cm "fix(A): one"
cm "fix(B): two"
push_main

shallow="$TMPROOT/$CASE/shallow"
git clone --quiet --depth 1 --no-single-branch "file://$ORIGIN" "$shallow"
cd "$shallow" || exit 1
git config user.name Dev
git config user.email dev@example.com

[[ $(git rev-parse --is-shallow-repository) == true ]] || _fail "fixture is not shallow"

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "sync must survive a shallow checkout"
assert_has "$OUT" "shallow clone detected" "and say what it did about it"
assert_has "$OUT" "fetch-depth: 0" "and how to avoid paying for it every run"

assert_on release/1.2 "fix(A): one" "first fix landed"
assert_on release/1.2 "fix(B): two" "second fix landed"
