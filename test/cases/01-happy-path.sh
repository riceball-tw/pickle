#!/usr/bin/env bash
# fixes land in trunk order, feats do not
new_repo
cut_release release/1.2

cm "fix(DS-1): one"
cm "feat(DS-2): shiny"
cm "fix(DS-3): two"
cm "feat(DS-4): shinier"
cm "fix(DS-5): three"
push_main

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "sync should succeed"

git fetch --quiet origin
assert_on     origin/release/1.2 "fix(DS-1): one"     "first fix landed"
assert_on     origin/release/1.2 "fix(DS-3): two"     "second fix landed"
assert_on     origin/release/1.2 "fix(DS-5): three"   "third fix landed"
assert_not_on origin/release/1.2 "feat(DS-2): shiny"  "feat must not be picked"
assert_not_on origin/release/1.2 "feat(DS-4): shinier" "feat must not be picked"

order=$(git log --format=%s --reverse origin/release/1.2 | grep '^fix' | tr '\n' '|')
assert_eq "fix(DS-1): one|fix(DS-3): two|fix(DS-5): three|" "$order" "picked oldest-first"

assert_has "$OUT" "3 picked" "summary counts the picks"
