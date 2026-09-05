# pickle — every error, and what to do

Diagnostics are printed to **stderr** as `pickle: <message>`. Match on the text
below. The exit code tells you which class of problem it is: `2` means the
invocation is wrong (fix it, do not retry), `3` means the environment is wrong,
`1` means a human has to make a decision.

## Exit 3 — environment

| message | cause | fix |
|---|---|---|
| `not a git repository` | Wrong working directory. | `cd` into the repo. |
| `a cherry-pick is already in progress; …` | A previous run or a person left a sequence open. | Look at `git status`. Finish it (`git cherry-pick --continue`) or abandon it (`git cherry-pick --abort`). Do not delete `.git/CHERRY_PICK_HEAD` by hand. |
| `working tree has uncommitted changes; commit or stash them first` | Dirty tree. | Commit or `git stash`. Ask the user before stashing their work — pickle refuses on purpose so nothing of theirs is lost. |
| `could not deepen the shallow clone` | `--unshallow` failed, usually no network or no remote access. | Re-clone with full history, or fix credentials. |
| `release branch 'X' does not exist; create it with: pickle cut …` | Typo, or the branch was never cut. | Check `git branch -a`. If it is genuinely a new release, `pickle cut` — but confirm with the user first, it pushes a new branch. |
| `local 'X' has diverged from 'origin/X'; reconcile them before running pickle` | Local release branch has commits the remote does not, or vice versa. pickle only fast-forwards. | Inspect `git log --oneline --left-right origin/X...X`. Reconcile deliberately; never force-push a release branch to make this go away without asking. |
| `'X' and 'Y' have no common ancestor` | The target was not cut from this trunk (or histories were rewritten). | Check `--target`/`--from` are the pair you meant. Grafting unrelated histories is not something pickle should paper over. |

## Exit 2 — usage

| message | fix |
|---|---|
| `--target is required (the release branch to pick onto)` | Pass `--target` or set `PICKLE_TARGET`. |
| `unknown command 'X' (try: pickle --help)` | Commands are `sync`, `status`, `cut`, `pick`, `skip`. |
| `unknown option '--x'` | Check the flag list in [reference.md](reference.md). |
| `--target needs a value` (and friends) | The flag was last on the line, or its value was consumed by another flag. |
| `X takes no positional arguments` | `sync`, `status` and `cut` take none. You probably meant `pick`. |
| `pick needs commits (SHAs, or '-' to read stdin)` / `skip needs at least one commit` | Supply them. If you piped a `git log`, remember the trailing `-`. |
| `not a commit in this repository: X` | The SHA is absent (shallow clone, unfetched, or a typo). `git fetch` first. |
| `--target and --from are the same branch (X)` | Check the invocation. |
| `--types is empty` | `--types ''` was passed. Give types, or use `--include`. |
| `trunk branch 'X' does not resolve to a commit` | Wrong `--from`, or trunk was never fetched. |
| `could not work out which branch is trunk; pass --from` | No `origin/HEAD` and no `main`/`master`/`trunk`. Pass `--from` explicitly. |

## Exit 1 — a human is needed

**`✗ conflict picking <sha>`** — the pick was aborted, the branch is clean,
nothing half-applied was pushed, and commits that applied before it were kept and
pushed. Everything queued behind it reports `not attempted (run stopped above)`.

Resolve it, keeping `-x`:

```bash
git fetch origin
git switch release/1.2
git cherry-pick -x <sha>
# fix the listed files
git add -A && git cherry-pick --continue
git push origin release/1.2
```

`git cherry-pick --continue` carries the `(cherry picked from commit …)` trailer
through the resolution, which is what stops the next `sync` proposing it again.
If you resolve it any other way — a fresh commit, a manual patch — pickle will
propose it again unless the resulting diff happens to hash identically. Record
the decision with `pickle skip` in that case.

Then re-run `pickle sync` to land the commits that were not attempted.

**`picked N commit(s) locally but the push to origin/X failed`** — the picks
exist on the local branch. Usual causes: the branch is protected, the CI token
lacks write access, or the remote moved. Do not lose them: check `git log`, then
either fix the permission and `git push origin X`, or hand the branch to someone
who can push. See [ci.md](ci.md) § Protected branches.

**`created X locally but the push to origin failed`** — same, for `cut`.

## Warnings (exit 0, but read them)

| warning | meaning |
|---|---|
| `no remote 'X'; working locally and not pushing` | Everything runs, nothing is pushed. Fine locally, almost always a misconfiguration in CI. |
| `shallow clone detected; deepening …` | pickle recovered by itself. Set `fetch-depth: 0` on the checkout so it does not pay for this every run. |
| `fetch from 'X' failed; continuing with the refs already local` | The result may be based on stale refs. In CI, treat this as a real problem. |
| `local 'X' differs from 'origin/X'; using 'origin/X' as trunk` | Your local trunk is stale or ahead. The remote won. |

## Results that look like errors but are not

- `skip (nothing left to apply)` — the change is already in the tree in a form
  patch-id could not recognise. pickle skipped the pick and moved on.
- `skip (already present (patch-id))` / `skip (already backported by hand (-x trailer))`
  — deduplication working. This is why `sync` is safe to run on a schedule.
- `nothing on main that is not already on release/1.2` — up to date.
