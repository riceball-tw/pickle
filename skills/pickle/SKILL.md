---
name: pickle
description: Backport hotfixes from a trunk branch onto a release branch with the `pickle` bash script (cut, sync, status, pick, skip) — cherry-picking by Conventional Commit type or regex, deduplicating with patch-id and `-x` trailers, and resolving the conflicts it stops on. Use whenever the task involves release branches, backporting, cherry-picking a fix into a release, "does release/X have this fix", maintaining a release branch, or wiring backports into CI.
---

# pickle

`pickle` cherry-picks commits from trunk onto a release branch using nothing but
`git` — no hosting-platform API, no config file, no state files. One bash script,
bash 4+ and git.

## Before anything else

1. **Is it installed?** `command -v pickle || ls ./pickle`. If not, see
   [reference.md](reference.md) § Install. Never `curl | bash`; never point CI at `main`.
2. **Preflight it will enforce anyway** (all exit 3): a git repo, a clean working
   tree, no cherry-pick in progress, full history (it deepens a shallow clone
   itself, with a warning).
3. **Run `status` first.** It is `sync` with mutation disabled — it never checks
   out a branch, never writes, never pushes. There is no reason not to.

```bash
NO_COLOR=1 pickle status --target release/1.2 --from main
```

## The mutation rule

`sync`, `pick`, `cut` and `skip` **push to the remote by default**. That is the
point of the tool, and it is not reversible with a local undo. So:

- Read `status` output back to the user and get agreement before the first
  mutating run in a session, unless they already told you to just do it.
- If you only want to see the plan for a mutating command, add `--dry-run`
  (works on all four, including `skip` and `cut`).
- `--no-push` lands commits on the local release branch and prints the `git push`
  to run. Useful when you want a human to eyeball the result.
- `pickle` returns you to the branch you started on, even when it dies.

## Commands

| | |
|---|---|
| `pickle cut --target release/1.2 --from main` | Create the release branch and push it. Once, at feature freeze. Fails (exit 3) if it already exists. |
| `pickle sync --target release/1.2 --from main` | Pick everything selected that is not already there, then push. Idempotent — run it as often as you like. |
| `pickle status --target release/1.2 --from main` | What `sync` would do. Mutates nothing, ever. |
| `pickle pick --target release/1.2 SHA...` | Cherry-pick named commits, ignoring the subject filter. `-` reads SHAs from stdin. |
| `pickle skip --target release/1.2 SHA --reason TEXT` | Record that a commit is deliberately not backported, so `sync` stops proposing it. |

`--target` is required everywhere. `--from` defaults to `origin/HEAD`, then a
remote `main`/`master`/`trunk`, then a local one.

## Reading the result

Exit code is the contract; the report is for humans.

| | |
|---|---|
| `0` | Everything selected landed, or there was nothing to do. |
| `1` | A commit conflicted and needs a human — **or** the picks landed locally but the push failed. |
| `2` | Usage error. Your invocation is wrong; fix it, do not retry it. |
| `3` | Repo/environment not in a workable state. Fix the environment. |

Report lines are stable enough to parse with `NO_COLOR=1` set:
`  <sha8>␣␣<subject padded>␣␣→ <status>`. Split on `→ `. Statuses are
`picked`, `would pick`, `skip (<reason>)`, `CONFLICT — needs a human`,
`not attempted (run stopped above)`. Diagnostics go to stderr; the report to stdout.

To verify independently rather than by parsing:
`git fetch origin && git log --oneline origin/release/1.2` — or re-run `status`
and confirm it now says nothing is outstanding.

## When it conflicts

`sync` picks in trunk order and **stops at the first conflict**. Everything that
applied before it is kept and pushed; the conflicting pick is aborted so the
branch is left clean; exit 1.

Do not work around this by reordering or by dropping the commit. The stop is
protecting order: if fix #4 depends on fix #2, landing #4 without #2 gives a
release branch that compiles and is wrong.

To resolve, follow the commands pickle printed. The `-x` is not optional — it
records `(cherry picked from commit …)`, which is how the next `sync` knows not
to propose this commit again:

```bash
git fetch origin
git switch release/1.2
git cherry-pick -x <sha>
# resolve the conflict in the listed files
git add -A && git cherry-pick --continue    # carries the -x trailer through
git push origin release/1.2
```

Then re-run `pickle sync` to land whatever was queued behind it.

`--keep-going` lands everything that applies and reports the rest (still exit 1).
Only offer it when the hotfixes are genuinely independent — it trades the order
guarantee away.

If a fix genuinely should not ship, record that decision instead of ignoring it:
`pickle skip --target release/1.2 <sha> --reason "depends on a feature not in 1.2"`.

## Choosing what gets picked

Default: Conventional Commit `fix` commits — the same rule semver uses for a
patch release. Breaking changes (`fix!:` or a `BREAKING CHANGE:` trailer) are
excluded, and merge commits are skipped.

```bash
pickle sync --target release/1.2 --types fix,perf          # more types
pickle sync --target release/1.2 --include '^\[HOTFIX\]'   # not conventional commits
pickle sync --target release/1.2 --include '^fix' --exclude 'WIP'
pickle sync --target release/1.2 --first-parent            # merge-based trunk
pickle sync --target release/1.2 --allow-breaking          # rarely right
```

`--include` **replaces** the type rule (it is not an addition to it); `--exclude`
is applied after it. Both are EREs matched against the subject line only.

If the rule is not a regex at all, any `git log` you can write becomes one:

```bash
git log --format=%H --grep=URGENT --author=oncall main \
  | pickle pick --target release/1.2 -
```

`pick` bypasses the *subject* filter only. Deduplication still applies, so
piping the same log twice is safe.

## How it knows what is already there

Two signals, both read off the release branch between the merge-base and its tip:

1. **`git patch-id`** hashes each commit's diff, ignoring SHA, message, author,
   date and whitespace — so a hand cherry-pick with a rewritten message still
   matches its original.
2. **The `-x` trailer**, for the one case patch-id cannot see: someone resolved
   a conflict, so the diff that landed differs from the original.

`pickle skip` writes an empty commit carrying that same trailer, which is why it
needs no new mechanism and leaves an auditable line in history.

A pick that turns out to be a no-op reports `skip (nothing left to apply)`. That
is not an error.

## More

- [reference.md](reference.md) — install, every flag, `PICKLE_*` environment
  variables, defaults, precedence, what pickle deliberately does not do.
- [troubleshooting.md](troubleshooting.md) — every error message it can emit,
  what caused it, and the fix.
- [ci.md](ci.md) — GitHub Actions (the bundled action), GitLab, and the two
  things every other CI has to get right.
- [development.md](development.md) — only if you are changing `pickle` itself:
  the test harness, conventions, shellcheck.
