# Homebrew bottling + bump-workflow simplification — design

**Date:** 2026-07-10
**Status:** Approved (design); implementation plan pending
**Repo:** `yo61/homebrew-tap`

## Problem

Installing the Python formulae in this tap (`jobhound`, `unifictl`) is a *source
build*: `brew install` downloads the sdist, then downloads and builds ~40 Python
dependencies into a virtualenv on the user's machine (~2 minutes, 2,309 files
for `jobhound`). This was raised upstream in
[Homebrew/discussions#6953](https://github.com/orgs/Homebrew/discussions/6953),
where a maintainer noted that a tap created with `brew tap-new` ships a workflow
to build binaries ("bottles") automatically.

Separately, the two `bump-<formula>.yaml` workflows (~270 lines each,
near-duplicates) carry substantial *incidental* complexity: hand-rolled Python
resource regeneration (`homebrew-pypi-poet` + `awk` + `sed` + regex surgery,
~57 lines) and a GraphQL `createCommitOnBranch` signing dance (~62 lines) to
satisfy the `required_signatures` rule on `main`.

## Goals

- **Fix the slow install** by publishing bottles (pre-built binary packages) so
  `brew install` downloads and un-tars a ready-made virtualenv instead of
  building from source.
- **Reduce moving parts** in the bump workflows by replacing hand-rolled logic
  with maintained Homebrew commands, and by letting the new bottling flow absorb
  the merge/signing responsibilities.
- Keep everything **within the tap repo** — no changes to the upstream
  `jobhound` / `unifictl` release workflows.

## Non-goals (explicitly out of scope)

- **Self-contained artifacts built upstream** (the `go-udap` model: PyInstaller/
  Nuitka binaries or `shiv`/`pex` zipapps produced by the tools' own release
  workflows, with a thin pointer formula). Recorded as a possible future
  migration — cheap for the pure-Python `unifictl`, real work for `jobhound`
  (compiled deps) — but not pursued now because it moves work upstream.
- **GitHub Packages / GHCR hosting** for bottles. Bottles are hosted on GitHub
  Releases.
- **Bottling the `go-udap` cask.** Casks ship pre-built binaries already.
- **Refactoring the two bump workflows into a reusable `workflow_call`
  workflow.** After simplification they are short; revisit if a third formula
  arrives.

## Decisions taken during brainstorming

| Decision | Choice |
| --- | --- |
| Bottle platform matrix | Full: `macos-26` (Apple Silicon), `macos-15-intel`, `ubuntu-latest` (Linux) |
| GitHub Action pinning | Pin every action to a SHA with a version comment (matches existing standard; keeps `zizmor` green) |
| Publish flow | Fully automated — `pr-pull` fires automatically once the bottle matrix is green; no human step |
| Auto-publish trigger | `workflow_run` hand-off (a separate `publish-bottles.yaml` reacts to `tests.yml` completing) |
| Bottle hosting | GitHub Releases (tap-new default) |
| Bump complexity | B1 — keep venv + bottles, replace hand-rolled logic with native `brew` commands |
| Upstream repo changes | None (all logic stays in the tap) |

## Architecture

### Target pipeline

```
upstream release ──repository_dispatch──▶ bump-<formula>.yaml  (simplified)
   1. validate version payload
   2. fetch sdist url + sha256 from the PyPI JSON API
   3. brew bump-formula-pr --write-only --no-audit --url --sha256   (edit head url/sha)
   4. brew update-python-resources [--exclude-packages …]           (regenerate resource blocks)
   5. commit to bump/<formula>-<version>, push as App, gh pr create (plain push; NO signing, NO auto-merge)
        │
Formula/*.rb changed ▼
   tests.yml ("brew test-bot", full matrix)
        └─ audit + install + test + build bottle → upload bottles_<os> artifacts
        │  on success AND head_branch starts with bump/
   publish-bottles.yaml (workflow_run) ▼
        └─ mint SEMANTIC_RELEASE_APP token
        └─ brew pr-pull <PR#>
             ├─ download bottle artifacts from the PR's test run
             ├─ create a GitHub Release, attach the bottle files
             ├─ add `bottle do … end` (root_url + per-platform sha256) to the formula
             └─ git-try-push to main as the App (bypasses the ruleset)
        └─ pr-pull closes the PR
```

Net effect for users: `brew install yo61/tap/<formula>` pours a bottle
(seconds) instead of building from source (~2 minutes).

### Components

Each unit has one purpose and a well-defined trigger/interface.

#### `bump-<formula>.yaml` (rewritten)

- **Purpose:** turn a new upstream version into an open PR that updates the
  formula (head url/sha + regenerated resource blocks).
- **Trigger:** `repository_dispatch` (`bump-<formula>`) from the upstream
  release, or manual `workflow_dispatch` with a version.
- **Steps:**
  1. Validate the version payload (kept from current workflow).
  2. Fetch the sdist `url` and `sha256` from `https://pypi.org/pypi/<pkg>/<ver>/json`.
  3. Wait for the PyPI *simple* index to publish the version (kept — Fastly lag
     means `pip`/`update-python-resources` can otherwise fail to resolve).
  4. `brew bump-formula-pr --write-only --no-audit --url=<url> --sha256=<sha>
     yo61/tap/<formula>` — edits the head url/sha256 in place.
  5. `brew update-python-resources yo61/tap/<formula> --install-dependencies`
     (jobhound adds `--exclude-packages <compiled deps>`) — regenerates the
     `resource` blocks for the new version.
  6. Commit the edited formula to `bump/<formula>-<version>`, push as the App,
     `gh pr create`.
- **Removed vs today:** `homebrew-pypi-poet` + `awk`/`sed`/regex regeneration;
  `createCommitOnBranch` GraphQL signing; the `gh pr merge --auto` dance; the
  inline `brew install` + `brew test`; and the tap-symlink / copy-back-after-
  `brew`-reset hacks that only existed to support inline install/test.
- **Depends on:** the tap being visible to `brew` (tap-symlink retained only if
  `bump-formula-pr` / `update-python-resources` require it; see Open questions);
  the `SEMANTIC_RELEASE_APP` credentials.

#### `tests.yml` (new — `brew test-bot`)

- **Purpose:** on every formula/cask PR, audit + install + test the changed
  artifact and, for formulae, build a bottle.
- **Trigger:** `pull_request` and `push` to `main`, filtered to
  `paths: [Formula/**, Casks/**]` (preserves the current "skip docs-only PRs"
  fast path that deleting `audit.yaml` would otherwise lose).
- **Matrix:** `macos-26`, `macos-15-intel`, and `ubuntu-latest` (container
  `ghcr.io/homebrew/brew:main`).
- **Steps:** `Homebrew/actions/setup-homebrew` → cache Bundler gems →
  `brew test-bot --only-cleanup-before` → `--only-setup` → `--only-tap-syntax`
  → (PR only) `--only-formulae` → upload `*.bottle.*` as `bottles_<os>`.
- **Interface out:** bottle artifacts attached to the workflow run; a
  success/failure conclusion consumed by `publish-bottles.yaml`.
- All actions pinned to SHA with a version comment.

#### `publish-bottles.yaml` (new — `brew pr-pull`)

- **Purpose:** once a bump PR's bottle matrix is green, attach the bottles to
  the formula and land it on `main`.
- **Trigger:** `workflow_run` on the `tests.yml` workflow, `types: [completed]`.
- **Guards (all must hold):**
  - `github.event.workflow_run.conclusion == 'success'`
  - `github.event.workflow_run.event == 'pull_request'`
  - `github.event.workflow_run.head_repository.full_name == github.repository`
    — the triggering run must come from a branch in **this** repo, not a fork.
    `workflow_run` runs privileged in the base repo, and a fork PR's
    `head_branch` name is attacker-controlled; without this clause a fork could
    name its branch `bump/x` and reach the write-capable App token. Bump PRs are
    always same-repo, so this costs the legitimate flow nothing.
  - `github.event.workflow_run.head_branch` starts with `bump/`
- The `workflow_run` trigger carries a scoped `# zizmor: ignore[dangerous-triggers]`
  with a justification comment: the trigger is inherent to the design and the
  same-repo + `bump/` guards make the privileged run safe.
- **Steps:** mint `SEMANTIC_RELEASE_APP` token → `setup-homebrew` →
  `Homebrew/actions/git-user-config` → resolve the PR number from
  `github.event.workflow_run.pull_requests[0].number` → `brew pr-pull --tap
  yo61/homebrew-tap <PR#>` (with `HOMEBREW_GITHUB_API_TOKEN` = App token) →
  `Homebrew/actions/git-try-push` to `main` with the App token.
- **Interface in:** the completed `tests.yml` run (for its bottle artifacts) and
  the PR number.

#### `audit.yaml` (deleted)

`brew test-bot` in `tests.yml` performs the same audit + install + test across a
real OS matrix, so the standalone audit workflow is redundant. The `paths`
filter on `tests.yml` preserves the docs-only fast-skip.

## Why the signing dance disappears

The `main` ruleset requires signed commits, requires PRs (no direct push), and
blocks force-pushes, with **one `always`-bypass actor: a GitHub App**
(`actor_id 3654569`, believed to be `SEMANTIC_RELEASE_APP`) and **no required
status checks**.

- The bump commit now targets a `bump/*` branch. The ruleset targets only the
  default branch, so `required_signatures` does not apply there — a plain
  `git commit` + `git push` is sufficient.
- The commits that reach `main` are created by `brew pr-pull` and pushed by the
  App via `git-try-push`. Because the App is an `always`-bypass actor, its push
  is exempt from `required_signatures` and the PR-required rule.

Therefore neither the `createCommitOnBranch` signing nor any local GPG signing
is needed anywhere in the new topology.

## Data flow

1. Upstream release → `repository_dispatch` with the new version.
2. `bump-<formula>.yaml` produces an edited `Formula/<formula>.rb` on a
   `bump/<formula>-<version>` branch and opens a PR.
3. `tests.yml` runs on the PR, builds a bottle per platform, uploads artifacts.
4. On success, `publish-bottles.yaml` runs `brew pr-pull`, which downloads those
   artifacts, uploads them to a new GitHub Release, writes a `bottle do` block
   into the formula, pushes the result to `main`, and closes the PR.
5. Users' `brew install` now finds a matching bottle and pours it.

## Error handling / fail-safe

- Any red matrix leg → `tests.yml` conclusion is not `success` →
  `publish-bottles.yaml` never runs → the PR stays open and `main` is untouched.
- A broken `update-python-resources` result surfaces as a failing PR to inspect,
  never as a silent bad merge.
- `brew pr-pull` failure (e.g. a missing artifact) leaves `main` untouched and
  the PR open; the publish step is re-runnable.
- A bottle only lands if its build, install, and `brew test` all passed on that
  platform.
- Users on an OS/arch with no matching bottle fall back to a source build —
  bottles are an optimization, never a hard requirement.

## Testing / rollout

1. Land the workflows; `actionlint` and `zizmor` must be clean.
2. Verify the ruleset bypass Integration (`actor_id 3654569`) is
   `SEMANTIC_RELEASE_APP`.
3. Prove the trigger end-to-end on the next real bump: confirm `tests.yml`
   builds bottles, `publish-bottles.yaml` fires and pushes, and
   `brew install --verbose yo61/tap/<formula>` reports "Pouring" (bottle) rather
   than building from source.

## Open questions (resolve during implementation)

- Does `brew bump-formula-pr --write-only` / `brew update-python-resources`
  require the checkout to be tapped (the symlink hack), or can they operate on
  the formula file in place? Determines whether the tap-symlink step stays in
  the bump workflow.
- Exact `--exclude-packages` set for `jobhound` (compiled deps: `lz4`,
  `pycryptodomex`, and any pulled in transitively such as `pydantic-core`).
  Confirm against a clean `update-python-resources` run.
- Confirm `brew pr-pull` closes the PR and deletes the `bump/*` branch, or
  whether branch cleanup needs an explicit step.
