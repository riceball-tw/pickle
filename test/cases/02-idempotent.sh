#!/usr/bin/env bash
# running sync twice picks nothing the second time
new_repo
cut_release release/1.2
cm "fix(A): one"
cm "fix(B): two"
push_main

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "first sync"
first=$(git rev-parse release/1.2)

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "second sync should be a clean no-op"
second=$(git rev-parse release/1.2)

assert_eq "$first" "$second" "branch must not move on a repeat run"
assert_has "$OUT" "0 picked" "second run picks nothing"
assert_has "$OUT" "already present (patch-id)" "and says why"
