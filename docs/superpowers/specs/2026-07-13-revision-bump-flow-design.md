# Design: first-class revision-bump flow

## Problem

The tap can bump a formula to a new upstream PyPI version (`bump.yaml` +
per-formula callers), but it has no path for a change that edits the formula
*source* without changing the upstream version — for example, adding
`generate_completions_from_executable` to `unifictl`'s `install` block.

Such a change needs a Homebrew `revision` bump: the PyPI version stays the same,
but the formula content changes, so the bottles must be rebuilt and `brew
upgrade` must be told to pick them up. Today the only way to publish new bottles
is the `bump/*` PR path, which `publish-bottles.yaml` auto-bottles and merges.
Hand-crafting a `bump/<formula>-<version>` branch for a revision works, but it is
implicit and easy to get wrong (branch name must carry a bare `X.Y.Z`, revision
must be set by hand, the PR reads like a version bump). We want a named,
on-demand operation instead.

## Goal

Ship formula-source changes that do not change the upstream version by bumping
Homebrew `revision`, rebuilding bottles, and squash-merging — triggered by an
explicit `workflow_dispatch`, reusing the existing signed-commit + bottle +
auto-merge machinery.

## Non-goals

- No change to the version-bump flow's externally observable behavior.
- No template/codegen for formula bodies (the substantive edit is human-authored).
- No change to `tests.yaml` or `publish-bottles.yaml`.

## Trigger model

Edit-on-branch + `workflow_dispatch`:

1. A human hand-edits `Formula/<formula>.rb` on a branch (the substantive source
   change) and pushes it. No PR needed, no `revision` line added by hand.
2. The human runs `revbump-<formula>` (`workflow_dispatch`) passing that branch
   as `source-ref`.
3. Automation computes and sets `revision`, opens a `bump/<formula>-<version>`
   PR, and lets the existing CI bottle + sign + squash-merge it.

Automation owns `revision`; the human never edits it.

## Components

### 1. `.github/actions/commit-formula-pr/action.yml` (new composite action)

The "shared tail", extracted verbatim in behavior from `bump.yaml`'s *"Commit via
the API and open the PR"* step.

- **Type:** composite action (not a reusable workflow). The tail commits the
  *edited workspace file*; a reusable workflow runs as a separate job and cannot
  see the caller's workspace without shuttling file contents through string
  inputs. A composite action runs in-job and shares the workspace — same DRY win,
  correct primitive.
- **Inputs:** `formula`, `version`, `branch`, `token` (App token), `pr-title`,
  `pr-body`.
- **Behavior:** create `branch` at main's HEAD via the git refs API; commit the
  workspace's `Formula/<formula>.rb` with GraphQL `createCommitOnBranch` (GitHub
  signs it, verified); open a PR to `main`.

### 2. `bump.yaml` (refactored)

Replace its inline commit+PR step with a call to the composite action. The
version-resolution, url/sha rewrite, and `update-python-resources` steps are
unchanged. Net observable behavior is identical; this is the one edit to working
release machinery and must be verified by a live version bump or careful review.

### 3. `revbump.yaml` (new reusable workflow) + `revbump-unifictl.yaml` / `revbump-jobhound.yaml` (thin callers)

- **Callers:** `workflow_dispatch` with inputs `source-ref` (branch holding the
  human's edit). Formula name is fixed per caller, mirroring `bump-*.yaml`.
- **`revbump.yaml` inputs:** `formula`, `source-ref`.
- **Steps:**
  1. Checkout `source-ref` (contains the human's edit).
  2. Read the upstream version from the formula (the `<formula>-X.Y.Z.tar.gz`
     url), validate it against `^[0-9]+\.[0-9]+\.[0-9]+([.\-][A-Za-z0-9._-]+)?$`.
  3. Read the current `revision` on `main`'s formula (absent → 0); set
     `revision = that + 1` in the workspace formula. Insert after the `license`
     line if absent; replace the existing `revision N` line otherwise.
  4. Guard: fail if `bump/<formula>-<version>` already exists on the remote, or
     if the workspace formula has no diff vs `main`.
  5. Mint the App token (as `bump.yaml` does) and call the composite action to
     open the `bump/<formula>-<version>` PR. PR title notes the revision, e.g.
     `chore(<formula>): revision <N>`.

### 4. `tests.yaml` / `publish-bottles.yaml` — unchanged

They already bottle → sign → squash-merge any `bump/*` PR and derive the release
tag from the plain `X.Y.Z` version. That is correct for a revision: `0.4.0_1`
bottle files attach to the existing `<formula>-0.4.0` release, and the bottle
block's `root_url` stays `<formula>-0.4.0`.

## Data flow

```
human edits Formula/<f>.rb on a branch, pushes
  -> dispatch revbump-<f>(source-ref)
    -> revbump: set revision = main.revision + 1
    -> composite action: open bump/<f>-<version> PR (signed commit)
      -> tests.yaml (test-bot): build revision bottles
        -> publish-bottles.yaml: upload bottles to <f>-<version> release,
           write bottle block, sign, squash-merge to main
          -> `brew upgrade` picks up the new revision
```

## Error handling

- `revbump.yaml` fails fast if the parsed version is malformed, if
  `bump/<formula>-<version>` already exists (a PR is already open), or if setting
  the revision produces no diff vs `main`.
- The composite action inherits `bump.yaml`'s existing failure surface (ref
  creation, GraphQL commit, PR open).

## Verification

- `brew style` on touched formulae; `actionlint` and `zizmor` on all workflows
  and the composite action (the repo already runs `zizmor` in CI).
- The completions fix (below) is shipped *through* this flow, so PR #2 is the
  end-to-end test of PR #1.

## Rollout for the triggering fix (two PRs)

- **PR #1** (human-reviewed, normal squash-merge to `main`): composite action +
  `bump.yaml` refactor + `revbump.yaml` + `revbump-*` callers + this spec +
  decision doc. Must land first so the `workflow_dispatch` is available on the
  default branch.
- **PR #2** (auto): the `unifictl` completions edit lives on
  `fix/unifictl-shell-completions` (adds `generate_completions_from_executable`
  to `install` and a `#compdef unifictl` assertion to `test`). Push it, dispatch
  `revbump-unifictl(source-ref=fix/unifictl-shell-completions)`; the auto PR
  bottles and merges, and `brew upgrade unifictl` then ships completions.

## Decision record

Log `decisions/2026-07-13-revision-bump-flow.md` capturing: why revisions are
needed, why a `workflow_dispatch` (not a branch-prefix convention), why a
composite action (not a reusable workflow) for the shared tail, and the
max-DRY extraction choice.
