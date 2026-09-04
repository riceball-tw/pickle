# pickle

A release backport tool that is only git.

At feature freeze you cut a release branch. For the next week or two, every
hotfix that lands on trunk has to be cherry-picked onto it — which gets
forgotten, done twice, or done in the wrong order. `pickle` is one bash script
that does it on a schedule.

It talks to nothing but `git`. No GitHub or GitLab API, no tokens beyond what
`git push` already needs, no config file, no state files, no bot account. The
same command runs identically on GitHub Actions, GitLab CI, Jenkins, Drone, or
your laptop, and keeps working if you change hosts.

```
$ pickle sync --target release/1.2 --from main

pickle  main → release/1.2

  f79f8151  fix(DS-1234): null deref in parser        → picked
  df968438  feat(DS-1251): bulk export                → skip (type not selected)
  0cd7b34a  fix(DS-1240): retry on 502                → skip (already present, patch-id)
  10e2907a  fix(DS-1260): off-by-one in log rotation  → picked
  3b3bb192  fix!: drop legacy endpoint                → skip (breaking change; --allow-breaking to include)

  2 picked, 3 skipped
  pushed release/1.2 to origin
```

## Install

One file, no dependencies beyond bash 4+ and git.

On **GitHub Actions** there is nothing to install — the action carries the
script, so the version is pinned by the tag you reference:

```yaml
- uses: riceball-tw/pickle@v1
  with:
    target: release/1.2
```

**Anywhere else**, pin to a release tag. Do not point CI at `main`: it moves,
and this tool writes to release branches.

```bash
curl -fsSL https://raw.githubusercontent.com/riceball-tw/pickle/v1.0.0/pickle \
  -o /usr/local/bin/pickle
chmod +x /usr/local/bin/pickle
```

## Use

```bash
# once, at feature freeze
pickle cut --target release/1.2 --from main

# then on a schedule, or on every merge to trunk
pickle sync --target release/1.2 --from main

# see what it would do, without doing it
pickle status --target release/1.2 --from main
```

`sync` is idempotent. Run it as often as you like.

It also puts you back on the branch you were standing on, so running it locally
does not quietly move you somewhere else.

## How it decides what to pick

By default it reads the Conventional Commit type off the subject line and takes
`fix` commits, which is the same rule semver uses for a patch release:

```bash
pickle sync --target release/1.2 --types fix,perf
```

If your team writes commits some other way, replace the rule with a regex:

```bash
pickle sync --target release/1.2 --include '^\[HOTFIX\]' --exclude 'WIP'
```

And if the rule is not expressible as a regex at all, pickle will read commits
on stdin, so any `git log` invocation you can write becomes a selection rule:

```bash
git log --format=%H --grep=URGENT --author=oncall main \
  | pickle pick --target release/1.2 -
```

Breaking changes (`fix!:`, or a `BREAKING CHANGE:` trailer) are excluded by
default — they are the one thing that should never appear in a patch release.
`--allow-breaking` includes them.

Merge commits are skipped by default, which is right if you squash-merge. If
your trunk carries the conventional subject on the merge commit instead, use
`--first-parent` and pickle will walk trunk's first-parent line and pick merges
with `-m 1`.

## How it avoids picking anything twice

This is the part that has to be right, because `sync` will run hundreds of times
against the same branch.

1. **patch-id.** `git patch-id` hashes a commit's *diff*, normalising whitespace
   and line numbers and ignoring the SHA, message, author and date. A hand
   cherry-pick made with no flags, a rewritten message and a different author
   still hashes identically to its original, so pickle sees it and skips it.
   This needs no discipline from anyone and covers almost every case.

2. **The `-x` trailer.** patch-id misses exactly one case: someone *resolved a
   conflict*, so the diff that landed differs from the original. That is what
   `git cherry-pick -x` is for — it records `(cherry picked from commit …)` in
   the message, and `git cherry-pick --continue` carries that line through the
   resolution. pickle scans the release branch for those trailers.

You never have to remember this. When a pick conflicts, pickle prints the exact
commands to run, `-x` included.

3. **`pickle skip`**, for the cases neither signal can see: a fix you decided
   not to ship, or a bug fixed directly on the release branch with a fresh
   commit. It writes an empty commit carrying the same trailer the detector
   already reads, so it needs no new mechanism and leaves an auditable line in
   history saying a human decided this on purpose.

```bash
pickle skip --target release/1.2 abc1234 --reason "depends on a feature not in 1.2"
```

## When something conflicts

pickle picks in trunk order and **stops at the first conflict**. Commits that
applied cleanly before it are kept and pushed; the conflicting one is aborted so
the branch is left clean and no conflict markers can reach the remote; the run
exits non-zero so the build goes red.

Stopping is the default because it preserves order. If fix #4 quietly depends on
fix #2, skipping #2 and landing #4 gives you a release branch that compiles and
is wrong. `--keep-going` opts into that trade when your hotfixes are genuinely
independent — it lands everything that applies and still exits non-zero.

```
  ✗ conflict picking 0cd7b34a  fix(DS-1240): retry on 502
      http.c

  the branch was left clean; nothing half-applied was pushed.

  resolve it locally:
    git fetch origin
    git switch release/1.2
    git cherry-pick -x 0cd7b34a
    # fix the conflict, then:
    git add -A && git cherry-pick --continue
    git push origin release/1.2
```

## Commands

| | |
|---|---|
| `pickle cut` | Create the release branch from trunk and push it. Once per release. |
| `pickle sync` | Pick everything matching the selection that is not already there, then push. The workhorse. |
| `pickle status` | Show what `sync` would do. Never mutates anything, never even checks out a branch. |
| `pickle pick` | Cherry-pick specific commits, ignoring the subject filter. `-` reads SHAs from stdin. |
| `pickle skip` | Record that a commit is deliberately not being backported. |

## Flags

| Flag | Default | |
|---|---|---|
| `--target BRANCH` | — | Release branch to pick onto. Required. A literal branch name; pickle assumes no naming convention. |
| `--from BRANCH` | `origin/HEAD`, else `main`/`master` | Trunk to pick from. |
| `--remote NAME` | `origin` | |
| `--types LIST` | `fix` | Conventional Commit types to pick, comma separated. |
| `--include REGEX` | — | Match subjects with this ERE instead of `--types`. |
| `--exclude REGEX` | — | Reject subjects matching this ERE, applied after include. |
| `--first-parent` | off | Walk trunk's first-parent line and pick merges with `-m 1`. |
| `--allow-breaking` | off | Also pick breaking changes. |
| `--keep-going` | off | On conflict, skip that commit and carry on. |
| `--dry-run` | off | Report; change nothing. |
| `--no-push` | off | Land commits locally but do not push. |
| `--no-fetch` | off | Work with the refs already local. |

Every flag also reads from a `PICKLE_`-prefixed environment variable
(`PICKLE_TARGET`, `PICKLE_FROM`, `PICKLE_TYPES`, `PICKLE_INCLUDE`,
`PICKLE_EXCLUDE`, `PICKLE_REMOTE`), since CI matrices set env more easily than
they build argv. Flags win over environment.

## Exit codes

| | |
|---|---|
| `0` | Everything selected was landed, or there was nothing to do. |
| `1` | A commit conflicted and needs a human. |
| `2` | Usage error. |
| `3` | The repository or environment is not in a state pickle can work in. |

A red build is the notification. pickle will not open an issue or comment on a
PR, because that would mean a platform API, which is the thing it is not.

## CI

See [`examples/`](examples/).

### GitHub Actions

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0          # required: cherry-pick needs history

- uses: riceball-tw/pickle@v1
  with:
    target: release/1.2
    from: main
```

| input | default | |
|---|---|---|
| `command` | `sync` | `sync`, `status`, `cut` or `skip` |
| `target` | — | Release branch. Required. |
| `from` | repo default branch | Trunk branch. |
| `types` | `fix` | Conventional Commit types, comma separated. |
| `include` / `exclude` | — | Subject regexes, as per the flags above. |
| `args` | — | Any other flags, verbatim: `--keep-going --allow-breaking` |

The job needs `permissions: contents: write` to push.

### Everything else

Two things matter:

- **Give the checkout full history.** `actions/checkout` defaults to
  `fetch-depth: 1`, which makes cherry-pick impossible. pickle detects a shallow
  clone and deepens it itself rather than failing, but set `fetch-depth: 0` so
  it does not pay for that on every run.
- **The job needs push rights** to the release branch. If `release/*` is a
  protected branch, a direct push will be rejected — pickle pushes straight to
  the branch by design, so either grant the CI identity an exception or run
  pickle somewhere that can push.

CI checkouts have no `user.email`, which normally makes `cherry-pick` refuse to
run. pickle supplies `pickle <noreply@pickle.invalid>` as the *committer* and
leaves the original author untouched, so `git log` still credits whoever wrote
the fix.

## What it deliberately does not do

Tagging and releases. PR or MR creation. Changelogs. Anything needing a hosting
platform's API. Forward-porting hotfixes from a release branch back to trunk.

pickle assumes you cut the release branch from trunk at feature freeze and
backport forward from there. It is not built for long-lived LTS branches that
assemble a release by picking onto a much older base — that works, but you will
spend your life resolving conflicts, and the tool cannot help with that.

## Tests

```bash
./test/run.sh          # everything
./test/run.sh conflict # cases matching a substring
KEEP=1 ./test/run.sh   # keep the fixture repos for inspection
```

The suite builds real git repositories in a temp dir and runs the real script
against them. Nothing is mocked, because how pickle behaves against actual git
is the entire product.
