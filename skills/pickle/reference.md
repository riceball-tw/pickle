# pickle — full reference

## Install

One file. No dependencies beyond bash 4+ and git. Pin to a release tag; do not
point anything at `main`, because it moves and this tool writes to release
branches.

```bash
curl -fsSL https://raw.githubusercontent.com/riceball-tw/pickle/v1.0.0/pickle \
  -o /usr/local/bin/pickle
chmod +x /usr/local/bin/pickle
```

On GitHub Actions there is nothing to install — the action carries the script, so
the version is pinned by the tag you reference. See [ci.md](ci.md).

`pickle --version` prints the version; `pickle --help` prints the full usage text.

## Commands

| command | mutates | pushes | notes |
|---|---|---|---|
| `cut` | creates a branch | yes | Refuses (exit 3) if the branch already exists locally or on the remote. |
| `sync` | cherry-picks | yes | Idempotent. The workhorse. |
| `status` | never | never | Forces `--dry-run --no-push`; never even checks out a branch. |
| `pick` | cherry-picks | yes | Takes SHAs as arguments, or `-` to read them from stdin, one per line. |
| `skip` | empty commits | yes | Needs at least one SHA. `--reason` becomes the commit body. |

`sync`, `status` and `cut` take no positional arguments (exit 2 if given any).

Explicit SHAs are resolved and reapplied **oldest-first**, regardless of the order
you passed them — which is what you want when piping `git log`, since that prints
newest first.

## Flags

| flag | default | |
|---|---|---|
| `--target BRANCH` | — | Release branch to pick onto. **Required.** A literal branch name; pickle assumes no naming convention. |
| `--from BRANCH` | see below | Trunk to pick from. |
| `--remote NAME` | `origin` | If the remote does not exist, pickle warns and works locally without pushing. |
| `--types LIST` | `fix` | Conventional Commit types, comma separated. Builds `^(a\|b)(\(scope\))?!?: `. |
| `--include REGEX` | — | ERE matched against the subject, **instead of** `--types`. |
| `--exclude REGEX` | — | ERE matched against the subject, applied after the include rule. |
| `--first-parent` | off | Walk trunk's first-parent line and pick merges with `-m 1`. Otherwise merges are skipped. |
| `--allow-breaking` | off | Also pick breaking changes. |
| `--keep-going` | off | On conflict, skip that commit and carry on. Still exits 1. |
| `--dry-run` | off | Report; change nothing. Valid on every command. |
| `--no-push` | off | Land locally, print the push command, do not push. |
| `--no-fetch` | off | Skip the initial fetch and use the refs already local. |
| `--reason TEXT` | — | Body for the empty commit written by `skip`. |
| `-h, --help` / `-V, --version` | | |

`--flag=value` and `--flag value` are both accepted. Everything after `--` is
treated as a positional SHA.

### `--from` resolution order

1. `--from` / `PICKLE_FROM`
2. `refs/remotes/<remote>/HEAD`
3. remote-tracking `main`, `master`, `trunk` — in that order
4. local `main`, `master`, `trunk`
5. otherwise exit 2, asking for `--from`

The **remote-tracking** ref is the source of truth for trunk: in CI the local
branch often does not exist, and locally it is often stale. If a local branch of
the same name disagrees with the remote one, pickle warns and uses the remote.

## Environment variables

| | |
|---|---|
| `PICKLE_TARGET`, `PICKLE_FROM`, `PICKLE_REMOTE`, `PICKLE_TYPES`, `PICKLE_INCLUDE`, `PICKLE_EXCLUDE` | Defaults for the matching flags. Empty is treated as unset. **Flags win.** |
| `NO_COLOR` | Disables colour. Set it whenever you intend to parse the output. |
| `GITHUB_STEP_SUMMARY` | If set and writable, the report is also appended there as a markdown table. |

CI matrices set environment more easily than they build argv, which is why every
flag has a variable.

## Selection rules in detail

- **Type filter.** `--types fix,perf` becomes the ERE
  `^(fix|perf)(\([^)]*\))?!?: ` — the subject must start with the type, an
  optional `(scope)`, an optional `!`, then `: ` with a space.
- **Breaking changes.** Detected as a subject matching `^type(scope)?!:` or a
  body line matching `^BREAKING[ -]CHANGE:`. Excluded unless `--allow-breaking`.
  They are the one thing that should never appear in a patch release.
- **Merges.** Skipped by default (`git rev-list --no-merges`), which is right for
  a squash-merge trunk. With `--first-parent`, pickle walks trunk's first-parent
  line and cherry-picks merges with `-m 1` — use it when your trunk carries the
  conventional subject on the merge commit.
- **`pick` sets "explicit".** It skips the type, exclude and breaking checks. It
  does **not** skip deduplication.

## Deduplication in detail

Both signals are gathered from `merge-base(target, from)..target` — i.e. only what
landed on the release branch after it was cut. Consequences worth knowing:

- A commit already on trunk *before* the branch point is not a candidate at all
  (it is not in `target..from`), so it never needs deduplicating.
- Rewriting release-branch history (rebase, force-push) can drop a `-x` trailer
  and make pickle propose a commit again. It will report a conflict or
  `nothing left to apply` rather than double-applying the change.
- `patch_id --stable` normalises whitespace and line numbers and ignores the SHA,
  message, author and date. Renames are disabled (`--no-renames`) so the hash is
  stable across rename detection settings.

## Committer identity

CI checkouts have no `user.email`, which normally makes `cherry-pick` refuse to
run. When the repo has no `user.name`/`user.email`, pickle exports
`GIT_COMMITTER_NAME=pickle` / `GIT_COMMITTER_EMAIL=noreply@pickle.invalid` — the
**committer** only. The original author is untouched, so `git log` still credits
whoever wrote the fix. (`skip` also sets `GIT_AUTHOR_*`, since its empty commits
have no original author.)

## What pickle deliberately does not do

Tagging and releases. PR/MR creation. Changelogs. Anything needing a hosting
platform's API — a red build is the notification. Forward-porting hotfixes from a
release branch back to trunk.

It assumes you cut the release branch from trunk at feature freeze and backport
forward. It is not built for long-lived LTS branches that assemble a release by
picking onto a much older base: that works, but you will spend your life
resolving conflicts and the tool cannot help with that.

Do not propose adding any of these to a `pickle` invocation — combine pickle with
other tools instead.
