#!/usr/bin/env bash
# with no git identity configured, authorship is preserved and pickle commits
new_repo
cut_release release/1.2

printf 'alice\n' >> f.txt
git add f.txt
GIT_AUTHOR_NAME=Alice GIT_AUTHOR_EMAIL=alice@example.com \
    git commit --quiet -m "fix(A): alice's fix"
push_main

git config --unset user.name
git config --unset user.email
git config user.email >/dev/null 2>&1 && _fail "fixture still has an identity"

run_pickle sync --target release/1.2 --from main
assert_status 0 "$STATUS" "cherry-pick must work with no configured identity"

author=$(git log -1 --format='%an <%ae>' release/1.2)
committer=$(git log -1 --format='%cn <%ce>' release/1.2)
assert_eq "Alice <alice@example.com>"        "$author"    "original author is preserved"
assert_eq "pickle <noreply@pickle.invalid>"  "$committer" "pickle is the committer"
