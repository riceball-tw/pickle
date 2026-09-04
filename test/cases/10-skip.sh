#!/usr/bin/env bash
# skip records a decision, and sync stops proposing the commit
new_repo
cut_release release/1.2
cm "fix(A): wanted"
cm "fix(B): deliberately not backported"
push_main
b=$(sha_of "fix(B)")

run_pickle skip --target release/1.2 --from main "$b" --reason "depends on a feature not in 1.2"
assert_status 0 "$STATUS" "skip should succeed"

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "sync after skip"
assert_on     release/1.2 "fix(A): wanted"                    "the other fix still lands"
assert_not_on release/1.2 "fix(B): deliberately not backported" "the skipped one does not"
assert_has "$OUT" "-x trailer" "the skip marker is what caught it"

body=$(git log --format=%B release/1.2 | grep -c "depends on a feature not in 1.2")
assert_eq 1 "$body" "the reason is recorded in history"

# skipping twice must not add a second marker
run_pickle skip --target release/1.2 --from main "$b"
assert_status 0 "$STATUS" "second skip"
assert_has "$OUT" "already recorded" "and is a no-op"
