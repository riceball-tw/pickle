#!/usr/bin/env bash
# --include works for teams that do not use conventional commits
new_repo
cut_release release/1.2

cm "[HOTFIX] urgent thing"
cm "just some work"
cm "[HOTFIX] another urgent thing"
cm "fix(A): conventional, not wanted here"
push_main

run_pickle sync --target release/1.2 --from main --include '^\[HOTFIX\]'
assert_status 0 "$STATUS" "sync with a custom include"

assert_on     release/1.2 "[HOTFIX] urgent thing"         "first hotfix landed"
assert_on     release/1.2 "[HOTFIX] another urgent thing" "second hotfix landed"
assert_not_on release/1.2 "just some work"                "unmarked commit skipped"
assert_not_on release/1.2 "fix(A): conventional, not wanted here" \
                                                          "--include replaces --types entirely"

# --exclude is applied on top of --include
run_pickle sync --target release/1.2 --from main --include '^\[HOTFIX\]' --exclude 'another'
assert_status 0 "$STATUS" "exclude on top of include"
