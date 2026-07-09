# Homebrew Bottling + Bump Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish pre-built bottles so `brew install` of this tap's Python formulae is fast, and rewrite the bump workflows around native `brew` commands so they stop hand-rolling resource generation and commit signing.

**Architecture:** A `brew test-bot` workflow builds a bottle per platform on every formula PR; a `workflow_run`-triggered `brew pr-pull` workflow attaches the bottles and lands the PR on `main` (pushing as the ruleset-bypass App). The `bump-<formula>.yaml` workflows shrink to: fetch the new sdist, apply it with `brew bump-formula-pr --write-only`, regenerate resources with `brew update-python-resources`, and open a PR — no poet, no GraphQL signing, no auto-merge (the bottling flow lands it).

**Tech Stack:** GitHub Actions, Homebrew (`test-bot`, `pr-pull`, `bump-formula-pr`, `update-python-resources`), `Homebrew/actions/*` composite actions, the `SEMANTIC_RELEASE_APP` GitHub App.

**Spec:** `docs/superpowers/specs/2026-07-10-homebrew-bottling-and-bump-simplification-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Pin every action to a SHA** with a trailing `# vX.Y.Z` (or `# master @ DATE`) comment. Approved pins:
  - `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2`
  - `actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9  # v6.1.0`
  - `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a  # v7.0.1`
  - `actions/create-github-app-token@1b10c78c7865c340bc4f6099eb2f838309f1e8c3  # v3.1.1`
  - `Homebrew/actions/setup-homebrew@6eaeff80e7e5c43087c0e5eb5aa82120399e9c91  # master @ 2026-05-22`
  - `Homebrew/actions/git-user-config@6eaeff80e7e5c43087c0e5eb5aa82120399e9c91  # master @ 2026-05-22`
  - `Homebrew/actions/git-try-push@6eaeff80e7e5c43087c0e5eb5aa82120399e9c91  # master @ 2026-05-22`
- **Every `run:` block starts with `set -euo pipefail`.**
- **Bottle matrix:** `macos-26` (Apple Silicon), `macos-15-intel`, `ubuntu-latest` (container `ghcr.io/homebrew/brew:main`).
- **Bottle hosting:** GitHub Releases (no `--github-packages`).
- **App:** `SEMANTIC_RELEASE_APP`, via secrets `SEMANTIC_RELEASE_APP_CLIENT_ID` and `SEMANTIC_RELEASE_APP_PRIVATE_KEY`. This App is the `always`-bypass actor on the `main` ruleset, so its pushes satisfy `required_signatures` and the PR-required rule without signing.
- **Validation gate for every workflow change:** `actionlint .github/workflows/<file>` and `zizmor .github/workflows/<file>` must both be clean (actionlint runs `shellcheck` on embedded `run:` scripts). These are the "tests" for this plan — GitHub Actions cannot be executed locally, so end-to-end proof happens in Task 6 (rollout).
- **Work on branch** `feat/bottling-and-bump-simplification` (already created; the spec is committed there).

---

### Task 1: Add the bottle-building CI (`tests.yml`)

**Files:**
- Create: `.github/workflows/tests.yml`

**Interfaces:**
- Produces: a workflow named **`brew test-bot`** (the `name:` field — `publish-bottles.yaml` in Task 2 references this exact string in its `workflow_run` trigger). On pull requests it uploads bottle artifacts named `bottles_<os>` matching `*.bottle.*`.

- [ ] **Step 1: Write `.github/workflows/tests.yml`**

```yaml
name: brew test-bot

on:
  push:
    branches:
      - main
    paths:
      - Formula/**
      - Casks/**
  pull_request:
    paths:
      - Formula/**
      - Casks/**

permissions:
  contents: read

jobs:
  test-bot:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-26, macos-15-intel]
        include:
          - os: ubuntu-latest
            container: ghcr.io/homebrew/brew:main
    runs-on: ${{ matrix.os }}
    container: ${{ matrix.container }}
    permissions:
      actions: read
      checks: read
      contents: read
      pull-requests: read
    steps:
      - name: Set up Homebrew
        id: set-up-homebrew
        uses: Homebrew/actions/setup-homebrew@6eaeff80e7e5c43087c0e5eb5aa82120399e9c91  # master @ 2026-05-22
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Cache Homebrew Bundler RubyGems
        uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9  # v6.1.0
        with:
          path: ${{ steps.set-up-homebrew.outputs.gems-path }}
          key: ${{ matrix.os }}-rubygems-${{ steps.set-up-homebrew.outputs.gems-hash }}
          restore-keys: ${{ matrix.os }}-rubygems-

      - name: Cleanup before
        run: brew test-bot --only-cleanup-before

      - name: Setup
        run: brew test-bot --only-setup

      - name: Tap syntax
        run: brew test-bot --only-tap-syntax

      - name: Build bottle
        if: github.event_name == 'pull_request'
        run: brew test-bot --only-formulae

      - name: Upload bottles as artifact
        if: always() && github.event_name == 'pull_request'
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a  # v7.0.1
        with:
          name: bottles_${{ matrix.os }}
          path: '*.bottle.*'
```

- [ ] **Step 2: Validate syntax and security**

Run: `actionlint .github/workflows/tests.yml && zizmor .github/workflows/tests.yml`
Expected: no output from `actionlint`; `zizmor` reports no findings (exit 0).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/tests.yml
git commit -m "ci: add brew test-bot workflow to build bottles"
```

---

### Task 2: Add the auto-publish workflow (`publish-bottles.yaml`)

**Files:**
- Create: `.github/workflows/publish-bottles.yaml`

**Interfaces:**
- Consumes: the `brew test-bot` workflow from Task 1 (via `workflow_run`), its bottle artifacts, and the PR whose head branch starts with `bump/`.
- Produces: bottles attached to a GitHub Release and a `bottle do` block committed to `main` (via `brew pr-pull` + `git-try-push` as the App).

- [ ] **Step 1: Write `.github/workflows/publish-bottles.yaml`**

```yaml
name: brew pr-pull

on:
  workflow_run:
    workflows: ["brew test-bot"]
    types:
      - completed

permissions:
  contents: read

jobs:
  pr-pull:
    runs-on: ubuntu-latest
    if: >-
      github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.event == 'pull_request' &&
      startsWith(github.event.workflow_run.head_branch, 'bump/')
    permissions:
      contents: read
    steps:
      - name: Mint App token
        id: app-token
        uses: actions/create-github-app-token@1b10c78c7865c340bc4f6099eb2f838309f1e8c3  # v3.1.1
        with:
          client-id: ${{ secrets.SEMANTIC_RELEASE_APP_CLIENT_ID }}
          private-key: ${{ secrets.SEMANTIC_RELEASE_APP_PRIVATE_KEY }}
          owner: ${{ github.repository_owner }}
          repositories: ${{ github.event.repository.name }}
          permission-contents: write
          permission-pull-requests: write

      - name: Set up Homebrew
        uses: Homebrew/actions/setup-homebrew@6eaeff80e7e5c43087c0e5eb5aa82120399e9c91  # master @ 2026-05-22
        with:
          token: ${{ steps.app-token.outputs.token }}

      - name: Set up git
        uses: Homebrew/actions/git-user-config@6eaeff80e7e5c43087c0e5eb5aa82120399e9c91  # master @ 2026-05-22

      - name: Pull bottles
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          HOMEBREW_GITHUB_API_TOKEN: ${{ steps.app-token.outputs.token }}
          HEAD_BRANCH: ${{ github.event.workflow_run.head_branch }}
        run: |
          set -euo pipefail
          pr=$(gh pr list --repo "$GITHUB_REPOSITORY" --head "$HEAD_BRANCH" \
                 --state open --json number --jq '.[0].number')
          if [[ -z "$pr" || "$pr" == "null" ]]; then
            echo "::error::no open PR found for branch $HEAD_BRANCH"
            exit 1
          fi
          echo "Pulling bottles for PR #$pr"
          brew pr-pull --debug --tap="$GITHUB_REPOSITORY" "$pr"

      - name: Push commits
        uses: Homebrew/actions/git-try-push@6eaeff80e7e5c43087c0e5eb5aa82120399e9c91  # master @ 2026-05-22
        with:
          token: ${{ steps.app-token.outputs.token }}
          branch: main
```

- [ ] **Step 2: Validate syntax and security**

Run: `actionlint .github/workflows/publish-bottles.yaml && zizmor .github/workflows/publish-bottles.yaml`
Expected: no `actionlint` output; `zizmor` clean.

Note: `zizmor` may warn about the `workflow_run` trigger's elevated context. If it flags the `Pull bottles` step, confirm the finding is the known `workflow_run` informational one and add a scoped `# zizmor: ignore[...]` with justification only if it is not a real issue. Do not broaden permissions to silence it.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/publish-bottles.yaml
git commit -m "ci: auto-publish bottles via pr-pull on green bump PRs"
```

---

### Task 3: Rewrite `bump-unifictl.yaml` (native commands, pure Python)

**Files:**
- Modify (full rewrite): `.github/workflows/bump-unifictl.yaml`

**Interfaces:**
- Consumes: `repository_dispatch` (`bump-unifictl`) or `workflow_dispatch` with a version; the `SEMANTIC_RELEASE_APP` secrets.
- Produces: a PR from branch `bump/unifictl-<version>` editing `Formula/unifictl.rb` — head url/sha256 updated and resource blocks regenerated. The PR is authored by the App so `tests.yml` runs on it.

- [ ] **Step 1: Replace the entire file with the rewrite**

```yaml
name: Bump unifictl formula

on:
  repository_dispatch:
    types: [bump-unifictl]
  workflow_dispatch:
    inputs:
      version:
        description: "unifictl version to bump to (e.g. 0.1.0 or v0.1.0)"
        required: true
        type: string

permissions: {}

jobs:
  bump:
    name: Bump unifictl
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Validate version payload
        id: version
        env:
          DISPATCH_VERSION: ${{ github.event.client_payload.version }}
          WORKFLOW_VERSION: ${{ github.event.inputs.version }}
        run: |
          set -euo pipefail
          raw="${DISPATCH_VERSION:-${WORKFLOW_VERSION:-}}"
          if [[ -z "$raw" ]]; then
            echo "::error::no version supplied (client_payload.version or workflow_dispatch.inputs.version)"
            exit 1
          fi
          v="${raw#v}"
          if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.\-][a-zA-Z0-9._-]+)?$ ]]; then
            echo "::error::Invalid version format: $raw"
            exit 1
          fi
          echo "version=$v" >> "$GITHUB_OUTPUT"
          echo "branch=bump/unifictl-$v" >> "$GITHUB_OUTPUT"

      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2
        with:
          persist-credentials: false

      - name: Fetch new sdist metadata
        id: sdist
        env:
          VERSION: ${{ steps.version.outputs.version }}
        run: |
          set -euo pipefail
          json=$(curl -fsSL "https://pypi.org/pypi/unifictl/${VERSION}/json")
          url=$(jq -r '.urls[] | select(.packagetype == "sdist") | .url' <<<"$json")
          sha=$(jq -r '.urls[] | select(.packagetype == "sdist") | .digests.sha256' <<<"$json")
          if [[ -z "$url" || -z "$sha" || "$url" == "null" || "$sha" == "null" ]]; then
            echo "::error::no sdist found on PyPI for unifictl==$VERSION"
            exit 1
          fi
          echo "url=$url" >> "$GITHUB_OUTPUT"
          echo "sha=$sha" >> "$GITHUB_OUTPUT"

      - name: Set up Homebrew
        uses: Homebrew/actions/setup-homebrew@6eaeff80e7e5c43087c0e5eb5aa82120399e9c91  # master @ 2026-05-22

      - name: Wait for PyPI simple index to publish new version
        env:
          VERSION: ${{ steps.version.outputs.version }}
        run: |
          set -euo pipefail
          # uv/pip resolve against the /simple/ index, served via Fastly and
          # lagging the JSON API by tens of seconds on first read.
          for i in $(seq 1 30); do
            if curl -sfH 'Cache-Control: no-cache' \
                 "https://pypi.org/simple/unifictl/" \
                 | grep -q "unifictl-${VERSION}\."; then
              echo "unifictl-${VERSION} visible on simple index (attempt $i)"
              exit 0
            fi
            sleep 4
          done
          echo "::error::unifictl-${VERSION} not visible on PyPI simple index after 120s"
          exit 1

      - name: Tap this checkout as yo61/tap
        run: |
          set -euo pipefail
          tap_dir="$(brew --repository)/Library/Taps/yo61/homebrew-tap"
          rm -rf "$tap_dir"
          ln -s "$GITHUB_WORKSPACE" "$tap_dir"

      - name: Bump url/sha256 and regenerate resources
        env:
          NEW_URL: ${{ steps.sdist.outputs.url }}
          NEW_SHA: ${{ steps.sdist.outputs.sha }}
          # Prevent brew's implicit auto-update from git-resetting the
          # symlinked tap (which would revert our edits).
          HOMEBREW_NO_AUTO_UPDATE: "1"
        run: |
          set -euxo pipefail
          brew bump-formula-pr --write-only --no-audit \
            --url="$NEW_URL" --sha256="$NEW_SHA" \
            yo61/tap/unifictl
          brew update-python-resources --install-dependencies yo61/tap/unifictl
          echo "::group::patched formula (head)"
          head -20 Formula/unifictl.rb
          echo "::endgroup::"

      - name: Mint App token
        id: app-token
        uses: actions/create-github-app-token@1b10c78c7865c340bc4f6099eb2f838309f1e8c3  # v3.1.1
        with:
          client-id: ${{ secrets.SEMANTIC_RELEASE_APP_CLIENT_ID }}
          private-key: ${{ secrets.SEMANTIC_RELEASE_APP_PRIVATE_KEY }}
          owner: ${{ github.repository_owner }}
          repositories: ${{ github.event.repository.name }}
          permission-contents: write
          permission-pull-requests: write

      - name: Commit and open PR
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          APP_TOKEN: ${{ steps.app-token.outputs.token }}
          APP_SLUG: ${{ steps.app-token.outputs.app-slug }}
          VERSION: ${{ steps.version.outputs.version }}
          BRANCH: ${{ steps.version.outputs.branch }}
        run: |
          set -euo pipefail
          if git diff --quiet -- Formula/unifictl.rb; then
            echo "::error::formula unchanged after bump; aborting"
            exit 1
          fi
          # Attribute the commit to the App's bot user. Branch is bump/*, not
          # main, so the required_signatures rule does not apply here; when
          # pr-pull later lands this on main it pushes as the bypass App.
          bot_user="${APP_SLUG}[bot]"
          bot_id=$(gh api "users/${bot_user}" --jq .id)
          git config user.name "$bot_user"
          git config user.email "${bot_id}+${bot_user}@users.noreply.github.com"
          git switch -c "$BRANCH"
          git add Formula/unifictl.rb
          git commit -m "chore(unifictl): bump to $VERSION"
          git push "https://x-access-token:${APP_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$BRANCH"
          gh pr create \
            --base main \
            --head "$BRANCH" \
            --title "chore(unifictl): bump to $VERSION" \
            --body "Automated bump triggered by unifictl's release workflow. tests.yml builds bottles; publish-bottles.yaml runs pr-pull once green."
```

- [ ] **Step 2: Validate syntax and security**

Run: `actionlint .github/workflows/bump-unifictl.yaml && zizmor .github/workflows/bump-unifictl.yaml`
Expected: no `actionlint` output; `zizmor` clean.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/bump-unifictl.yaml
git commit -m "ci: rewrite bump-unifictl around native brew commands"
```

---

### Task 4: Rewrite `bump-jobhound.yaml` (native commands, `[mcp]` extra + excludes)

**Files:**
- Modify (full rewrite): `.github/workflows/bump-jobhound.yaml`

**Interfaces:**
- Consumes: `repository_dispatch` (`bump-jobhound`) or `workflow_dispatch` with a version; the `SEMANTIC_RELEASE_APP` secrets.
- Produces: a PR from branch `bump/jobhound-<version>` editing `Formula/jobhound.rb`.

This is Task 3's workflow with three differences: the package name (`jobhound`), the branch/dispatch names, and the resource-regeneration command, which must include the `[mcp]` extra and exclude the brewed compiled packages.

- [ ] **Step 1: Start from the committed `bump-unifictl.yaml` and rename the identifiers**

Task 3 committed `.github/workflows/bump-unifictl.yaml`, so copy it and apply the string substitutions on disk (no need to re-read Task 3):

```bash
cp .github/workflows/bump-unifictl.yaml .github/workflows/bump-jobhound.yaml
# Rename every unifictl identifier to jobhound. These strings only ever
# refer to the package/formula/branch, so a blanket replace is safe:
#   name, dispatch type, PyPI package, /simple/ path, formula path,
#   branch (bump/jobhound-$v), PR titles, error messages.
sed -i '' 's/unifictl/jobhound/g' .github/workflows/bump-jobhound.yaml
```

Then verify the head is correct — the job name, dispatch type, and branch line should now read:

```yaml
name: Bump jobhound formula
# ...
  repository_dispatch:
    types: [bump-jobhound]
# ...
          echo "branch=bump/jobhound-$v" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 2: Replace the resource-regeneration step body**

Replace the **"Bump url/sha256 and regenerate resources"** step (which the `sed` left calling plain `update-python-resources`) with the jobhound version that adds the `[mcp]` extra and excludes the brewed compiled packages:

```yaml
      - name: Bump url/sha256 and regenerate resources
        env:
          NEW_URL: ${{ steps.sdist.outputs.url }}
          NEW_SHA: ${{ steps.sdist.outputs.sha }}
          HOMEBREW_NO_AUTO_UPDATE: "1"
        run: |
          set -euxo pipefail
          brew bump-formula-pr --write-only --no-audit \
            --url="$NEW_URL" --sha256="$NEW_SHA" \
            yo61/tap/jobhound
          # jobhound installs the [mcp] extra; cffi/cryptography/pycparser
          # (brewed cryptography), pydantic/pydantic-core (brewed pydantic),
          # and rpds-py (brewed rpds-py) are provided via depends_on and must
          # NOT be vendored as resources (that would drag a Rust toolchain in).
          brew update-python-resources --install-dependencies \
            --package-name "jobhound[mcp]" \
            --exclude-packages "cffi,cryptography,pycparser,pydantic,pydantic-core,rpds-py" \
            yo61/tap/jobhound
          echo "::group::patched formula (head)"
          head -20 Formula/jobhound.rb
          echo "::endgroup::"
```

After the `sed`, every other identifier is already correct: the `Fetch new sdist metadata` step queries `https://pypi.org/pypi/jobhound/${VERSION}/json`, the `Wait for PyPI simple index` step polls `https://pypi.org/simple/jobhound/`, and the PR titles read `chore(jobhound): ...`.

- [ ] **Step 3: Validate syntax and security**

Run: `actionlint .github/workflows/bump-jobhound.yaml && zizmor .github/workflows/bump-jobhound.yaml`
Expected: no `actionlint` output; `zizmor` clean.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/bump-jobhound.yaml
git commit -m "ci: rewrite bump-jobhound around native brew commands"
```

---

### Task 5: Retire `audit.yaml` and update the README

**Files:**
- Delete: `.github/workflows/audit.yaml`
- Modify: `README.md` (the "How content lands here" section)

**Interfaces:**
- Consumes: `tests.yml` from Task 1 (now the sole PR audit/install/test path).

**Rationale:** `brew test-bot` in `tests.yml` audits + installs + tests across a real OS matrix, so the standalone `audit.yaml` is redundant. The `paths: [Formula/**, Casks/**]` filter on `tests.yml` preserves the "skip docs-only PRs" fast path.

- [ ] **Step 1: Confirm no workflow references `audit.yaml` by name**

Run: `rg -n 'audit\.yaml|audit\.yml' .github README.md`
Expected: only comment references inside `audit.yaml` itself, if any. If another workflow references it, stop and reconcile before deleting.

- [ ] **Step 2: Delete the workflow**

```bash
git rm .github/workflows/audit.yaml
```

- [ ] **Step 3: Update the README "How content lands here" section**

Replace the two `jobhound`/`unifictl` bullets and the trailing audit sentence with text describing the new flow. The current block is:

```markdown
- `jobhound` is updated by `.github/workflows/bump-jobhound.yaml` in this repo, triggered via `repository_dispatch` from `yo61/jobhound`'s release workflow.
- `unifictl` is updated by `.github/workflows/bump-unifictl.yaml` in this repo, triggered via `repository_dispatch` from `yo61/unifictl`'s release workflow.

Every push and PR runs `brew audit --strict --new` and `brew install` (+ `brew test` for formulae) against changed artifacts via `.github/workflows/audit.yaml`.
```

Replace it with:

```markdown
- `jobhound` and `unifictl` are updated by `.github/workflows/bump-jobhound.yaml` / `bump-unifictl.yaml`, triggered via `repository_dispatch` from each tool's release workflow. Each bump opens a PR that regenerates the formula with `brew bump-formula-pr` + `brew update-python-resources`.

Formula PRs are audited, installed, tested, and bottled across macOS (Apple Silicon + Intel) and Linux by `.github/workflows/tests.yml` (`brew test-bot`). When that run is green on a `bump/*` PR, `.github/workflows/publish-bottles.yaml` runs `brew pr-pull` to attach the bottles to a GitHub Release and land the formula on `main`, so `brew install` pours a pre-built bottle instead of building from source.
```

- [ ] **Step 4: Validate**

Run: `rg -n 'audit\.yaml' README.md; test ! -f .github/workflows/audit.yaml && echo "audit.yaml removed"`
Expected: no README hits; prints `audit.yaml removed`.

- [ ] **Step 5: Commit**

```bash
git add -A .github/workflows/audit.yaml README.md
git commit -m "ci: retire audit.yaml in favour of test-bot; document bottling"
```

---

### Task 6: Rollout verification (manual)

**Files:** none (verification only).

This task cannot be unit-tested; it is the end-to-end proof. Do these in order and record results in the PR description.

- [ ] **Step 1: Confirm the ruleset bypass actor is `SEMANTIC_RELEASE_APP`**

Run:
```bash
gh api repos/yo61/homebrew-tap/rulesets/16783297 --jq '.bypass_actors'
gh api users/semantic-release-app --jq '.id'   # adjust slug if different; compare to actor_id 3654569
```
Expected: the ruleset's `bypass_actors[0].actor_id` (currently `3654569`) corresponds to `SEMANTIC_RELEASE_APP`. If it does not, `pr-pull`'s push to `main` will be rejected by `required_signatures` — stop and resolve before relying on auto-publish.

- [ ] **Step 2: Open the implementation PR and watch `tests.yml`**

Push the branch and open the PR. Because the PR touches `.github/workflows/**` and `docs/**` but not `Formula/**`, `tests.yml` will **not** run on it (paths filter). This is expected. Merge it once reviewed.

- [ ] **Step 3: Prove bottling on the next real bump (or a scratch bump)**

Trigger a bump manually: `gh workflow run bump-unifictl.yaml -f version=<current-or-next-version>`. Then verify, in order:
- The bump job opens a `bump/unifictl-<v>` PR authored by the App.
- `tests.yml` runs on that PR and each matrix leg uploads a `bottles_<os>` artifact.
- On success, `publish-bottles.yaml` fires, `brew pr-pull` creates a Release with the bottle files, commits a `bottle do` block, pushes to `main`, and closes the PR.
- `brew update yo61/tap && brew install --verbose yo61/tap/unifictl` reports **"Pouring unifictl--<v>.<platform>.bottle.tar.gz"** rather than building from source.

- [ ] **Step 4: If `git-try-push` fails to find the tap directory**

The `Push commits` step relies on `git-try-push`'s default directory being the `pr-pull`-modified tap. If it errors that there is nothing to push or the wrong repo, add `directory: $(brew --repository)/Library/Taps/yo61/homebrew-tap` (as a literal path input) to the `git-try-push` step in `publish-bottles.yaml` and re-run. Record the outcome.

- [ ] **Step 5: Confirm branch cleanup**

Check that `brew pr-pull` closed the PR and deleted the `bump/*` branch. If the branch lingers, add a final `gh api -X DELETE repos/$GITHUB_REPOSITORY/git/refs/heads/$HEAD_BRANCH` step (using the App token) to `publish-bottles.yaml`.

---

## Notes for the implementer

- **You cannot run GitHub Actions locally.** The per-task "validation" is `actionlint` + `zizmor` (static). Real behaviour is proven only in Task 6. Do not claim the pipeline works before Task 6 passes.
- **`brew update-python-resources` needs a clean pip pointing at public PyPI.** CI runners are clean; a local reproduction needs no private index configured (a Treasure Data Artifactory `extra-index-url` was removed from this machine during planning). The command also emits `--uploaded-prior-to=<timestamp>`, which requires the index to expose upload-time metadata (public PyPI does).
- **Order matters:** land Tasks 1–2 (bottling machinery) before Tasks 3–4 (which remove auto-merge), so bump PRs always have a path to `main`. Task 5 last.
- **`--exclude-packages` list for jobhound** is authoritative from the pre-rewrite `bump-jobhound.yaml` (`cffi`, `cryptography`, `pycparser`, `pydantic`, `pydantic-core`, `rpds-py`). If a future jobhound release adds a new compiled dep wired via `depends_on`, extend this list.
```
