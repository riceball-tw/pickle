#!/usr/bin/env bash
# status and --dry-run select identically to sync and mutate nothing
new_repo
cut_release release/1.2
cm "fix(A): one"
cm "feat(B): nope"
cm "fix(C): two"
push_main

head_before=$(git rev-parse HEAD)
branch_before=$(git rev-parse release/1.2)
on_before=$(git symbolic-ref --short HEAD)

run_pickle status --target release/1.2 --from main
assert_status 0 "$STATUS" "status should succeed"
assert_has "$OUT" "would pick" "status previews the picks"
assert_has "$OUT" "[dry run]" "and says it is a preview"
planned=$(printf '%s\n' "$OUT" | grep -- '→ would pick' | awk '{print $1}' | tr '\n' '|')

assert_eq "$head_before"   "$(git rev-parse HEAD)"           "status must not move HEAD"
assert_eq "$branch_before" "$(git rev-parse release/1.2)"    "status must not move the branch"
assert_eq "$on_before"     "$(git symbolic-ref --short HEAD)" "status must not switch branches"

run_pickle sync --target release/1.2 --from main --dry-run
assert_status 0 "$STATUS" "--dry-run should succeed"
assert_eq "$branch_before" "$(git rev-parse release/1.2)" "--dry-run must not move the branch"

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "the real run"
actual=$(printf '%s\n' "$OUT" | grep '→ picked' | awk '{print $1}' | tr '\n' '|')

assert_eq "$planned" "$actual" "status predicted exactly what sync did"
