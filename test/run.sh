#!/usr/bin/env bash
#
# pickle test harness.
#
# Builds real throwaway git repositories in a temp dir and runs the real script
# against them. No bats, no fixtures checked in, no mocking of git — the whole
# point of pickle is how it behaves against actual git, so that is what we test.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PICKLE=$(cd "$HERE/.." && pwd)/pickle
export PICKLE

[[ -x $PICKLE ]] || { echo "cannot find an executable pickle at $PICKLE" >&2; exit 1; }

# Keep the developer's own git config out of the results entirely.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_EDITOR=true
export NO_COLOR=1
export LC_ALL=C.UTF-8

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/pickle-test.XXXXXX")
KEEP=${KEEP:-0}
cleanup() { (( KEEP )) && { echo "kept: $TMPROOT"; return; }; rm -rf "$TMPROOT"; }
trap cleanup EXIT
export TMPROOT

# ---------------------------------------------------------------------------
# Assertions. Each one aborts its case on failure; other cases still run.
# ---------------------------------------------------------------------------

_fail() {
    printf '    \033[31mFAIL\033[0m %s\n' "$1" >&2
    [[ -n ${2:-} ]] && printf '%s\n' "$2" | sed 's/^/         /' >&2
    exit 1
}

assert_status() { # expected actual message
    [[ $1 == "$2" ]] || _fail "$3: expected exit $1, got $2" "${OUT:-}"
}
assert_eq() {     # expected actual message
    [[ $1 == "$2" ]] || _fail "$3" "expected: $1
actual:   $2"
}
assert_has() {    # haystack needle message
    [[ $1 == *"$2"* ]] || _fail "$3" "expected to find: $2
in:
$1"
}
assert_lacks() {  # haystack needle message
    [[ $1 != *"$2"* ]] || _fail "$3" "expected NOT to find: $2
in:
$1"
}

# Subjects present on a ref, one per line.
subjects_on() { git log --format=%s "$1"; }

assert_on() {     # ref subject message
    subjects_on "$1" | grep -qxF "$2" || _fail "$3" "'$2' is not on $1. subjects:
$(subjects_on "$1")"
}
assert_not_on() { # ref subject message
    subjects_on "$1" | grep -qxF "$2" && _fail "$3" "'$2' should not be on $1. subjects:
$(subjects_on "$1")"
    return 0
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A bare "origin" plus a working clone, with one commit on main already pushed.
new_repo() {
    local d="$TMPROOT/$CASE"
    rm -rf "$d"; mkdir -p "$d"
    ORIGIN="$d/origin.git"
    WORK="$d/work"
    git init --quiet --bare --initial-branch=main "$ORIGIN"
    git init --quiet -b main "$WORK"
    cd "$WORK" || exit 1
    git config user.name  "Dev"
    git config user.email "dev@example.com"
    git config advice.detachedHead false
    git remote add origin "$ORIGIN"
    echo base > f.txt
    git add f.txt
    git commit --quiet -m "chore: initial"
    git push --quiet -u origin main
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    export ORIGIN WORK
}

# cm <subject> [file] [content]
#
# Each commit touches its own file by default. Appending everything to one file
# would make unrelated commits conflict as soon as one of them is not picked,
# which is real git behaviour but not what most of these cases are about.
cm() {
    local subject=$1 file=${2:-} content=${3:-}
    if [[ -z $file ]]; then
        file=f$(printf '%s' "$subject" | tr -c 'a-zA-Z0-9' '-' | cut -c1-40).txt
    fi
    [[ -n $content ]] || content="$subject-$RANDOM$RANDOM"
    printf '%s\n' "$content" >> "$file"
    git add -- "$file"
    git commit --quiet -m "$subject"
}

# cmbody <subject> <body> [file]
cmbody() {
    local subject=$1 body=$2 file=${3:-}
    [[ -n $file ]] || file=f$(printf '%s' "$subject" | tr -c 'a-zA-Z0-9' '-' | cut -c1-40).txt
    printf '%s\n' "$subject-$RANDOM$RANDOM" >> "$file"
    git add -- "$file"
    git commit --quiet -m "$subject" -m "$body"
}

push_main() { git push --quiet origin main; }

# Cut a release branch the way pickle cut would, and push it.
cut_release() {
    git branch "$1" main
    git push --quiet -u origin "$1"
}

sha_of() { git log --format=%H --grep="$1" -1 main; }

# Run pickle without -e killing the case, capturing output and status.
# OUT and STATUS are read by the case files that call this.
# shellcheck disable=SC2034
run_pickle() {
    set +e
    OUT=$("$PICKLE" "$@" 2>&1)
    STATUS=$?
    set -e
    return 0
}

export -f _fail assert_status assert_eq assert_has assert_lacks \
          subjects_on assert_on assert_not_on new_repo cm cmbody \
          push_main cut_release sha_of run_pickle

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

PASS=0 FAIL=0
declare -a FAILED=()

only=${1:-}

export CASE
for case_file in "$HERE"/cases/*.sh; do
    CASE=$(basename "$case_file" .sh)
    [[ -n $only && $CASE != *"$only"* ]] && continue

    desc=$(sed -n '2s/^# *//p' "$case_file")
    printf '  %-34s %s\n' "$CASE" "$desc"

    if ( set -eo pipefail; . "$case_file" ) 2>&1; then
        PASS=$(( PASS + 1 ))
    else
        FAIL=$(( FAIL + 1 ))
        FAILED+=( "$CASE" )
    fi
done

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL )); then
    printf '  failed: %s\n' "${FAILED[*]}"
    exit 1
fi
