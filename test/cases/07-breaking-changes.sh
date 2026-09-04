#!/usr/bin/env bash
# breaking changes are excluded unless --allow-breaking
new_repo
cut_release release/a
cut_release release/b

cm "fix(A): ordinary"
cm "fix!: breaking bang"
cmbody "fix(C): quiet breaker" "BREAKING CHANGE: the api moved"
push_main

run_pickle sync --target release/a --from main
assert_status 0 "$STATUS" "default run"
assert_on     release/a "fix(A): ordinary"      "ordinary fix landed"
assert_not_on release/a "fix!: breaking bang"   "bang syntax excluded"
assert_not_on release/a "fix(C): quiet breaker" "BREAKING CHANGE body excluded"
assert_has "$OUT" "breaking change" "and it says why"

run_pickle sync --target release/b --from main --allow-breaking
assert_status 0 "$STATUS" "--allow-breaking run"
assert_on release/b "fix(A): ordinary"      "ordinary fix landed"
assert_on release/b "fix!: breaking bang"   "bang syntax included"
assert_on release/b "fix(C): quiet breaker" "BREAKING CHANGE body included"
