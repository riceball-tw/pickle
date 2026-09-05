# pickle in CI

Two things matter on every platform, and only two:

1. **Full history.** `actions/checkout` defaults to `fetch-depth: 1`, which makes
   cherry-pick impossible. pickle detects a shallow clone and deepens it rather
   than failing, but set the depth so it does not pay for that on every run.
2. **Push rights** to the release branch, for the identity the job runs as.

Exit 1 on conflict fails the job on purpose: a red build is how the team finds
out that a fix needs backporting by hand. pickle will not open an issue or
comment on a PR, because that would mean a platform API — the thing it is not.

## GitHub Actions

The action carries the script, so the tag you reference pins the version.

```yaml
name: backport to release

on:
  schedule:
    - cron: '0 2 * * *'          # nightly
  push:
    branches: [main]             # or immediately on every merge to trunk
  workflow_dispatch:

permissions:
  contents: write                # pickle pushes straight to the release branch

jobs:
  backport:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0         # required

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
| `include` / `exclude` | — | Subject regexes. |
| `args` | — | Any other flags, verbatim: `--keep-going --allow-breaking` |

Inputs reach the script as `PICKLE_*` environment variables and are never
interpolated into a `run:` body — a `${{ }}` expansion inside `run:` is
substituted as text before bash sees it, which turns any attacker-controlled
input into arbitrary shell. Preserve that property in anything you write.

When `GITHUB_STEP_SUMMARY` is set, pickle also appends the report there as a
markdown table, so the run summary shows what was picked without opening logs.

A working example lives in the pickle repo at `examples/github-actions.yml`.

## GitLab CI

`CI_JOB_TOKEN` cannot push. Use a Project Access Token with `write_repository`,
stored as a masked variable.

```yaml
backport:
  stage: .post
  image: alpine:3.20
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  variables:
    GIT_DEPTH: 0                  # full history
    RELEASE_BRANCH: release/1.2
  before_script:
    - apk add --no-cache bash git curl
    - curl -fsSL https://raw.githubusercontent.com/riceball-tw/pickle/v1.0.0/pickle -o /usr/local/bin/pickle
    - chmod +x /usr/local/bin/pickle
    - git remote set-url origin
        "https://oauth2:${PICKLE_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"
  script:
    - pickle sync --target "$RELEASE_BRANCH" --from "$CI_DEFAULT_BRANCH"
```

A working example lives in the pickle repo at `examples/gitlab-ci.yml`.

## Anywhere else (Jenkins, Drone, CircleCI, cron)

```bash
curl -fsSL https://raw.githubusercontent.com/riceball-tw/pickle/v1.0.0/pickle -o /usr/local/bin/pickle
chmod +x /usr/local/bin/pickle
git fetch --unshallow || true            # or clone with full history
PICKLE_TARGET=release/1.2 PICKLE_FROM=main pickle sync
```

Setting `PICKLE_*` is usually easier than building argv in a matrix. No
`user.email` is needed: pickle supplies the committer identity itself.

## Protected branches

pickle pushes straight to the branch by design. If `release/*` is protected the
push is rejected and the run exits 1 with the picks sitting on the local branch.
Either grant the CI identity an exception, or run in preview mode and let a human
land it:

```yaml
      - uses: riceball-tw/pickle@v1
        with:
          command: status
          target: release/1.2
```

## Scheduling

`sync` is idempotent, so frequency is a preference, not a correctness question.
Nightly is the common choice; on every push to trunk gives the fastest feedback
but a failing conflict will then re-fail every run until someone resolves it —
which is the intended pressure.
