# Revision-Bump Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `workflow_dispatch`-triggered flow that ships formula-source changes which do not change the upstream PyPI version, by bumping Homebrew `revision` and reusing the existing bottle + sign + auto-merge machinery.

**Architecture:** Extract `bump.yaml`'s "commit the edited formula via signed GraphQL commit + open PR" tail into a local composite action. `bump.yaml` calls it (behavior unchanged). A new reusable `revbump.yaml` + thin per-formula callers check out a human-edited branch, set `revision = main.revision + 1`, and call the same composite action to open a `bump/<formula>-<version>` PR that existing CI bottles and merges.

**Tech Stack:** GitHub Actions (reusable workflows, composite actions), `gh` CLI, GraphQL `createCommitOnBranch`, Homebrew test-bot. Lint with `actionlint` and `zizmor`.

## Global Constraints

- Never interpolate `${{ inputs.* }}` / `${{ github.* }}` directly inside `run:` blocks — map to `env:` first, reference as `$VAR` (zizmor template-injection rule; matches `bump.yaml`).
- Pin third-party actions to a full SHA with a version comment (`actions/create-github-app-token@1b10c78c7865c340bc4f6099eb2f838309f1e8c3  # v3.1.1`).
- App token minting uses `repositories: ${{ github.event.repository.name }}`, `owner: ${{ github.repository_owner }}`, `permission-contents: write`, `permission-pull-requests: write`.
- Branch name for any bottled PR is exactly `bump/<formula>-<version>` where `<version>` is a bare `X.Y.Z` (no revision suffix) — `publish-bottles.yaml` parses it and validates `^[0-9]+\.[0-9]+\.[0-9]+([.\-][A-Za-z0-9._-]+)?$`.
- `revision` line placement in the formula: immediately after the `license "…"` line, before the blank line preceding `bottle do` (verified `brew style`-clean).
- Job scripts start with `set -euo pipefail`.

---

### Task 1: Composite action `commit-formula-pr` + refactor `bump.yaml` to use it

**Files:**
- Create: `.github/actions/commit-formula-pr/action.yml`
- Modify: `.github/workflows/bump.yaml:186-228` (replace the "Commit via the API and open the PR" step)

**Interfaces:**
- Produces: composite action at `./.github/actions/commit-formula-pr` with inputs `formula`, `branch`, `token`, `commit-headline`, `pr-title`, `pr-body`. Creates `refs/heads/<branch>` at `main`'s HEAD, commits `Formula/<formula>.rb` from the workspace via signed GraphQL `createCommitOnBranch`, opens a PR to `main`. Consumed by `bump.yaml` (this task) and `revbump.yaml` (Task 2).

- [ ] **Step 1: Create the composite action**

Create `.github/actions/commit-formula-pr/action.yml`:

```yaml
name: Commit formula and open PR
description: >-
  Create a bump/* branch at main's HEAD, commit the workspace's
  Formula/<formula>.rb as a GitHub-signed GraphQL commit, and open a PR.
  The signed commit lets publish-bottles squash-merge onto signature-protected
  main with no ruleset bypass.

inputs:
  formula:
    description: Formula name (Formula/<formula>.rb is committed)
    required: true
  branch:
    description: Branch to create and open the PR from (e.g. bump/unifictl-0.4.0)
    required: true
  token:
    description: App token with contents:write and pull-requests:write
    required: true
  commit-headline:
    description: Commit message headline
    required: true
  pr-title:
    description: Pull request title
    required: true
  pr-body:
    description: Pull request body
    required: true

runs:
  using: composite
  steps:
    - shell: bash
      env:
        GH_TOKEN: ${{ inputs.token }}
        FORMULA: ${{ inputs.formula }}
        BRANCH: ${{ inputs.branch }}
        HEADLINE: ${{ inputs.commit-headline }}
        PR_TITLE: ${{ inputs.pr-title }}
        PR_BODY: ${{ inputs.pr-body }}
      run: |
        set -euo pipefail
        if git diff --quiet -- "Formula/${FORMULA}.rb"; then
          echo "::error::Formula/${FORMULA}.rb unchanged; nothing to commit"
          exit 1
        fi
        # Create the commit through GitHub's GraphQL createCommitOnBranch:
        # GitHub builds and signs the commit server-side (committer "GitHub",
        # verified), so the PR carries no "commits must have verified signatures"
        # block and publish-bottles can squash-merge it onto the signature-
        # protected main with no ruleset bypass. The Contents REST API does not
        # sign — only createCommitOnBranch and the web UI do.
        base_sha=$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/main" --jq .object.sha)
        # createCommitOnBranch commits onto an existing branch, so create it
        # (at main's HEAD) first; the mutation then adds the one commit.
        gh api -X POST "repos/${GITHUB_REPOSITORY}/git/refs" \
          -f ref="refs/heads/${BRANCH}" -f sha="$base_sha" >/dev/null
        jq -nc \
          --arg repo "$GITHUB_REPOSITORY" \
          --arg branch "$BRANCH" \
          --arg oid "$base_sha" \
          --arg headline "$HEADLINE" \
          --arg path "Formula/${FORMULA}.rb" \
          --arg contents "$(base64 -w0 "Formula/${FORMULA}.rb")" \
          '{query:"mutation($input:CreateCommitOnBranchInput!){createCommitOnBranch(input:$input){commit{oid}}}",
            variables:{input:{
              branch:{repositoryNameWithOwner:$repo,branchName:$branch},
              message:{headline:$headline},
              expectedHeadOid:$oid,
              fileChanges:{additions:[{path:$path,contents:$contents}]}}}}' \
          | gh api graphql --input - >/dev/null
        gh api -X POST "repos/${GITHUB_REPOSITORY}/pulls" \
          -f title="$PR_TITLE" \
          -f head="${BRANCH}" \
          -f base=main \
          -f body="$PR_BODY" >/dev/null
```

- [ ] **Step 2: Replace the tail step in `bump.yaml`**

In `.github/workflows/bump.yaml`, replace the entire `- name: Commit via the API and open the PR` step (lines 186-228) with:

```yaml
      - name: Commit and open the PR
        if: steps.gate.outputs.ready == 'true'
        uses: ./.github/actions/commit-formula-pr
        with:
          formula: ${{ inputs.formula }}
          branch: ${{ steps.gate.outputs.branch }}
          token: ${{ steps.app-token.outputs.token }}
          commit-headline: "chore(${{ inputs.formula }}): bump to ${{ steps.gate.outputs.version }}"
          pr-title: "chore(${{ inputs.formula }}): bump to ${{ steps.gate.outputs.version }}"
          pr-body: "Automated bump triggered by ${{ inputs.formula }}'s release workflow. tests.yaml builds bottles; publish-bottles.yaml adds the bottle and squash-merges once green."
```

Leave the `- name: Mint App token` step (lines 174-184) exactly as-is — the composite action consumes `steps.app-token.outputs.token`.

- [ ] **Step 3: Lint the action and workflow**

Run: `actionlint .github/workflows/bump.yaml && zizmor .github/actions/commit-formula-pr/action.yml .github/workflows/bump.yaml`
Expected: no errors. (`actionlint` validates the workflow; `zizmor` audits both for injection/permission issues.)

- [ ] **Step 4: Verify the refactor is behavior-identical**

Confirm by inspection that the composite action reproduces the old step's three operations in order (branch create at main HEAD → signed GraphQL commit of the formula → open PR) and that `bump.yaml`'s title/headline/body strings are byte-identical to the originals. Run:

`git -C . show HEAD:.github/workflows/bump.yaml | sed -n '186,228p'` (original, from the pre-change commit) and compare the interpolated strings against Step 2.
Expected: title, headline, and body text match the originals character-for-character.

- [ ] **Step 5: Commit**

```bash
git add .github/actions/commit-formula-pr/action.yml .github/workflows/bump.yaml
git commit -m "refactor: extract commit-formula-pr composite action from bump.yaml"
```

---

### Task 2: `revbump.yaml` reusable workflow

**Files:**
- Create: `.github/workflows/revbump.yaml`

**Interfaces:**
- Consumes: `./.github/actions/commit-formula-pr` (Task 1).
- Produces: reusable workflow `revbump.yaml` with `workflow_call` inputs `formula` (string, required) and `source-ref` (string, required); secrets `SEMANTIC_RELEASE_APP_CLIENT_ID`, `SEMANTIC_RELEASE_APP_PRIVATE_KEY`. Opens a `bump/<formula>-<version>` PR that sets `revision = main.revision + 1`. Consumed by the callers in Task 3.

- [ ] **Step 1: Create the reusable workflow**

Create `.github/workflows/revbump.yaml`:

```yaml
name: Revision bump

# Ship a formula-source change that does NOT change the upstream PyPI version
# (e.g. a new `generate_completions_from_executable` line): bump Homebrew
# `revision`, open a bump/<formula>-<version> PR, and let tests.yaml +
# publish-bottles.yaml bottle, sign, and squash-merge it.
#
# The substantive formula edit is authored by a human on `source-ref`; this
# workflow only sets `revision` (main's revision + 1) and opens the PR. The
# release tag / root_url stay <formula>-<version> — revision bottles (0.4.0_1)
# coexist in the existing version's release.

on:
  workflow_call:
    inputs:
      formula:
        description: "Formula name (Formula/<formula>.rb)"
        required: true
        type: string
      source-ref:
        description: "Branch holding the human's formula edit"
        required: true
        type: string
    secrets:
      SEMANTIC_RELEASE_APP_CLIENT_ID:
        required: true
      SEMANTIC_RELEASE_APP_PRIVATE_KEY:
        required: true

permissions: {}

jobs:
  revbump:
    name: Revision-bump ${{ inputs.formula }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2
        with:
          ref: ${{ inputs.source-ref }}
          persist-credentials: false

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

      - name: Set revision and derive branch
        id: rev
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          FORMULA: ${{ inputs.formula }}
        run: |
          set -euo pipefail
          f="Formula/${FORMULA}.rb"

          # Upstream version from the sdist url (same parse as bump.yaml).
          current_file=$(grep -oE "${FORMULA}-[0-9][^\"/]*\.tar\.gz" "$f" | head -1)
          version="${current_file#"${FORMULA}"-}"
          version="${version%.tar.gz}"
          if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.\-][A-Za-z0-9._-]+)?$ ]]; then
            echo "::error::could not parse a valid version from $f (got '$version')"
            exit 1
          fi

          # Next revision = (revision on main) + 1. Absent on main => 0.
          main_rev=$(gh api "repos/${GITHUB_REPOSITORY}/contents/${f}?ref=main" --jq '.content' \
            | base64 -d | grep -oE '^  revision [0-9]+' | grep -oE '[0-9]+$' || true)
          main_rev="${main_rev:-0}"
          new_rev=$((main_rev + 1))

          # Set (not increment) the workspace revision, so re-runs are idempotent
          # regardless of what source-ref carries.
          if grep -qE '^  revision [0-9]+' "$f"; then
            sed -i -E "s/^  revision [0-9]+/  revision ${new_rev}/" "$f"
          else
            awk -v rev="  revision ${new_rev}" '
              { print }
              /^  license / && !done { print rev; done=1 }
            ' "$f" > "$f.tmp"
            mv "$f.tmp" "$f"
          fi

          branch="bump/${FORMULA}-${version}"
          if gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/${branch}" >/dev/null 2>&1; then
            echo "::error::branch ${branch} already exists (a PR is already open)"
            exit 1
          fi

          {
            echo "version=$version"
            echo "revision=$new_rev"
            echo "branch=$branch"
          } >> "$GITHUB_OUTPUT"

      - name: Open the revision-bump PR
        uses: ./.github/actions/commit-formula-pr
        with:
          formula: ${{ inputs.formula }}
          branch: ${{ steps.rev.outputs.branch }}
          token: ${{ steps.app-token.outputs.token }}
          commit-headline: "chore(${{ inputs.formula }}): revision ${{ steps.rev.outputs.revision }}"
          pr-title: "chore(${{ inputs.formula }}): revision ${{ steps.rev.outputs.revision }}"
          pr-body: "Revision bump (upstream ${{ steps.rev.outputs.version }} unchanged). tests.yaml builds bottles; publish-bottles.yaml adds the bottle and squash-merges once green."
```

- [ ] **Step 2: Lint**

Run: `actionlint .github/workflows/revbump.yaml && zizmor .github/workflows/revbump.yaml`
Expected: no errors.

- [ ] **Step 3: Verify the branch/version invariants by inspection**

Confirm: (a) `branch` is `bump/<formula>-<version>` with a bare `X.Y.Z` version (satisfies `publish-bottles.yaml`'s guard); (b) the `revision` regex/insertion matches the Global Constraints placement; (c) no `${{ }}` appears inside any `run:` block.
Expected: all three hold.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/revbump.yaml
git commit -m "feat: add revbump reusable workflow for revision bumps"
```

---

### Task 3: Per-formula `revbump-*` callers

**Files:**
- Create: `.github/workflows/revbump-unifictl.yaml`
- Create: `.github/workflows/revbump-jobhound.yaml`

**Interfaces:**
- Consumes: `./.github/workflows/revbump.yaml` (Task 2).
- Produces: two `workflow_dispatch` entry points, each fixing `formula` and passing `source-ref` through.

- [ ] **Step 1: Create the unifictl caller**

Create `.github/workflows/revbump-unifictl.yaml`:

```yaml
name: Revision-bump unifictl

# Thin caller: dispatch a Homebrew revision bump for a human-edited unifictl
# formula on `source-ref`. See revbump.yaml for the mechanics.

on:
  workflow_dispatch:
    inputs:
      source-ref:
        description: "Branch holding the unifictl formula edit"
        required: true
        type: string

permissions: {}

jobs:
  revbump:
    permissions:
      contents: read
    uses: ./.github/workflows/revbump.yaml
    secrets:
      SEMANTIC_RELEASE_APP_CLIENT_ID: ${{ secrets.SEMANTIC_RELEASE_APP_CLIENT_ID }}
      SEMANTIC_RELEASE_APP_PRIVATE_KEY: ${{ secrets.SEMANTIC_RELEASE_APP_PRIVATE_KEY }}
    with:
      formula: unifictl
      source-ref: ${{ github.event.inputs.source-ref }}
```

- [ ] **Step 2: Create the jobhound caller**

Create `.github/workflows/revbump-jobhound.yaml` — identical except the name and `formula`:

```yaml
name: Revision-bump jobhound

# Thin caller: dispatch a Homebrew revision bump for a human-edited jobhound
# formula on `source-ref`. See revbump.yaml for the mechanics.

on:
  workflow_dispatch:
    inputs:
      source-ref:
        description: "Branch holding the jobhound formula edit"
        required: true
        type: string

permissions: {}

jobs:
  revbump:
    permissions:
      contents: read
    uses: ./.github/workflows/revbump.yaml
    secrets:
      SEMANTIC_RELEASE_APP_CLIENT_ID: ${{ secrets.SEMANTIC_RELEASE_APP_CLIENT_ID }}
      SEMANTIC_RELEASE_APP_PRIVATE_KEY: ${{ secrets.SEMANTIC_RELEASE_APP_PRIVATE_KEY }}
    with:
      formula: jobhound
      source-ref: ${{ github.event.inputs.source-ref }}
```

- [ ] **Step 3: Lint**

Run: `actionlint .github/workflows/revbump-unifictl.yaml .github/workflows/revbump-jobhound.yaml && zizmor .github/workflows/revbump-unifictl.yaml .github/workflows/revbump-jobhound.yaml`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/revbump-unifictl.yaml .github/workflows/revbump-jobhound.yaml
git commit -m "feat: add revbump-unifictl and revbump-jobhound dispatch callers"
```

---

### Task 4: Decision record

**Files:**
- Create: `decisions/2026-07-13-revision-bump-flow.md`

- [ ] **Step 1: Write the decision doc**

Create `decisions/2026-07-13-revision-bump-flow.md`:

```markdown
## Decision: Add a workflow_dispatch revision-bump flow to the tap

A `workflow_dispatch` (revbump-<formula>.yaml → revbump.yaml) ships formula-source
changes that don't change the upstream PyPI version, by setting Homebrew
`revision = main.revision + 1` and opening a `bump/<formula>-<version>` PR that the
existing tests.yaml + publish-bottles.yaml bottle, sign, and squash-merge. The
bump.yaml commit+PR tail is extracted into a `.github/actions/commit-formula-pr`
composite action shared by both flows.

## Context: A tap-only fix (adding generate_completions_from_executable to
unifictl's install block) changes the formula but not the upstream version, so it
needs a Homebrew revision bump and fresh bottles. The tap had no path for that —
only version bumps get bottled and merged.

## Alternatives considered:
- Reuse the bump/ prefix by hand for a revision — implicit, easy to get wrong.
- New branch-prefix convention (revbump/*) with pure push-to-publish — more
  convention to remember, less automation.
- Fully-automated caller that regenerates the formula from a template — the
  substantive edit is human-authored, so there's nothing to codegen.
- Add a `revision:` mode to bump.yaml — tangles version-bump and revision logic
  in one file with interleaved conditionals.
- Reusable workflow (not composite action) for the shared tail — a reusable
  workflow is a separate job and can't see the caller's edited workspace file
  without shuttling it through string inputs.

## Reasoning: The dispatch model keeps the human owning the substantive edit while
automation owns the revision increment + publish, and it's explicit. A composite
action is the right primitive for sharing in-job steps that operate on the
workspace file. publish-bottles already derives the release tag from the branch's
bare version, so revision bottles need no change there.

## Trade-offs accepted: The bump.yaml refactor touches proven release machinery
(mitigated: behavior-identical, verified by the next live version bump). Shipping
a revision fix is two PRs (automation, then the fix) because workflow_dispatch
only runs from the default branch.
```

- [ ] **Step 2: Commit**

```bash
git add decisions/2026-07-13-revision-bump-flow.md
git commit -m "docs: record revision-bump flow decision"
```

---

## Post-merge: ship the unifictl completions fix (PR #2)

Not a code task — the operational follow-up once PR #1 (Tasks 1-4) is merged to `main`:

1. Push the existing `fix/unifictl-shell-completions` branch (install/test edit, no `revision`).
2. Actions → **Revision-bump unifictl** → Run workflow, `source-ref = fix/unifictl-shell-completions`.
3. The auto-opened `bump/unifictl-0.4.0` PR bottles and squash-merges.
4. Verify: `brew update && brew upgrade unifictl`, then in a fresh zsh `unifictl <TAB>` lists commands (a `_unifictl` lands in `$(brew --prefix)/share/zsh/site-functions/`).

## Self-Review

- **Spec coverage:** composite action (Task 1) ✓; bump.yaml refactor (Task 1) ✓; revbump.yaml (Task 2) ✓; per-formula callers (Task 3) ✓; tests.yaml/publish-bottles unchanged ✓ (no task, by design); revision ownership by automation (Task 2, Step 1) ✓; error handling — bad version / existing branch / no-diff (Task 2 Step 1 + action diff guard) ✓; decision doc (Task 4) ✓; two-PR rollout (Post-merge section) ✓.
- **Placeholder scan:** none — every step has literal file content or an exact command.
- **Type consistency:** composite action inputs (`formula`, `branch`, `token`, `commit-headline`, `pr-title`, `pr-body`) match both call sites (Task 1 Step 2, Task 2 Step 1); `steps.rev.outputs.{version,revision,branch}` defined and consumed within Task 2.
