# Changing pickle itself

Only relevant if you are modifying the script in this repository, not using it.

## Layout

| | |
|---|---|
| `pickle` | The whole tool. One bash file, ~900 lines, no sourcing. |
| `action.yml` | Composite GitHub Action wrapping the script. |
| `examples/` | CI configs, kept working by hand. |
| `.claude-plugin/` | `plugin.json` + `marketplace.json`, so the repo is its own Claude Code plugin marketplace. |
| `skills/pickle/` | The agent skill. Also what `npx skills add riceball-tw/pickle` fetches. |
| `test/run.sh` | The harness. |
| `test/cases/NN-name.sh` | One case each, sourced by the harness. |
| `.github/workflows/test.yml` | shellcheck (pinned) + the suite + a live action run. |

## Tests

```bash
./test/run.sh            # everything
./test/run.sh conflict   # cases whose name matches a substring
KEEP=1 ./test/run.sh     # keep the fixture repos for inspection
```

The suite builds real git repositories in a temp dir and runs the real script
against them. Nothing is mocked, because how pickle behaves against actual git is
the entire product. Preserve that: a new case creates a repo with `new_repo`,
makes commits with `cm`, runs the tool with `run_pickle`, and asserts on
`$STATUS`, `$OUT`, and the actual refs (`assert_on`, `assert_not_on`).

The harness pins `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null` and
`NO_COLOR=1` so a developer's own git config cannot change the results. Keep it
that way.

## Conventions in the script

- `set -euo pipefail`; exit codes are the four `EX_*` constants and are part of
  the public contract — do not add or renumber them casually.
- Diagnostics via `warn`/`die` to **stderr**; the report is data and goes to
  **stdout**.
- Every option has a flag and a `PICKLE_`-prefixed variable; flags win. There is
  deliberately no config file and no state file.
- Comments explain *why* a line exists (which git failure mode it handles), not
  what it does. Match that register.
- Fields are joined with `SEP=$'\x1f'` so empty fields survive `read`.

## Before proposing a change

- `shellcheck pickle` must be clean at the pinned version (v0.11.0); CI installs
  that exact version on purpose, so an image bump cannot turn into a red build.
- `./test/run.sh` must pass.
- Anything user-visible — a flag, an exit code, a message — needs the README, the
  in-script `usage()` text, and this skill updated together.
- Releasing: `PICKLE_VERSION` in the script, `version` in
  `.claude-plugin/plugin.json`, and the plugin entry's `version` in
  `.claude-plugin/marketplace.json` must move together, or plugin users quietly
  keep running a cached copy. `claude plugin validate . --strict` must pass.
- Check the request against `README.md` § "What it deliberately does not do"
  before implementing it. Tagging, changelogs, PR creation and anything needing a
  platform API are out of scope by design, not by omission.
