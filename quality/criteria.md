# Quality criteria

Evaluated before a task in this tap is marked complete. Each block follows the
format in the global quality gate.

## Category: Formula and cask style

## Criteria:

    - `brew style Formula Casks` reports no offenses
    - `depends_on` lines are ordered as rubocop expects (build deps first)

## Severity: blocking

## Source: tests.yaml `--only-tap-syntax` gate; decisions/2026-08-12-scheduled-tap-style-autofix.md

## Last triggered: never

## Category: Python formula dependencies

## Criteria:

    - Every name in a formula's `pypi_packages exclude_packages` appears in the
      `exclude-packages` input of its `bump-<formula>.yaml` caller, and vice versa
    - Every excluded package is provided by a `depends_on ... => :no_linkage` formula
    - A `=> :build` dependency carries a trailing comment naming the resource
      chain that needs it (e.g. `# for xdg-base-dirs > uv_build > maturin`)
    - A formula sharing a resource with a formula being fixed has been checked
      for the same failure

## Severity: blocking

## Source: PR #10; decisions/2026-10-02-rust-build-dep-for-uv-build.md

## Last triggered: 2026-10-02

## Category: Formula tests

## Criteria:

    - A formula's `test do` loads every optional feature the formula installs
      (for jobhound, `import mcp.server` for the `[mcp]` extra), not just
      `--version`

## Severity: warning

## Source: PR #138: homebrew-core's cryptography dropped python@3.13, so
`jh mcp` failed to import while `jh --version` and test-bot still passed

## Last triggered: 2026-10-09

## Category: Bottles and releases

## Criteria:

    - The `bottle` block's `root_url` tag matches the formula's version
      (including any `revision`)
    - A formula change with an unchanged upstream version either goes through
      the revbump flow or the PR explains why the published bottles stay valid
    - No change republishes a version already bottled on `main`

## Severity: blocking

## Source: decisions/2026-07-13-revision-bump-flow.md; decisions/2026-09-13-bottle-content-invariant.md

## Last triggered: never

## Category: Workflows

## Criteria:

    - `actionlint .github/workflows/` and `zizmor .github/workflows/` are clean,
      or each ignore carries a justification comment
    - Actions are pinned to a full SHA with a version comment
    - `actions/checkout` sets `persist-credentials: false`
    - Non-trivial `run:` blocks start with `set -euo pipefail`

## Severity: blocking

## Source: global GitHub Actions standards; decisions/2026-07-13-zizmor-paths-filter.md

## Last triggered: never

## Category: Landing changes

## Criteria:

    - Every commit reaching `main` arrives through a PR and is signed
    - Nothing pushes to `main` directly
    - Superseding a `bump/*` PR closes it and deletes its branch before the
      bump is re-dispatched

## Severity: blocking

## Source: decisions/2026-07-13-signed-commits-via-api-drop-bypass.md; bump.yaml branch-exists gate

## Last triggered: never

## Category: Verification claims

## Criteria:

    - The PR states what its CI run exercises and what it does not (test-bot on
      a non-bump PR builds the versions on `main`, not the pending bump)
    - A fix for a failed bump is confirmed by the re-run bump's test-bot, not
      only by the fix PR's own run

## Severity: warning

## Source: PR #127 / PR #128

## Last triggered: 2026-10-02

## Category: Decisions

## Criteria:

    - A change to the release pipeline, or one that reverses an earlier
      decision, has a `decisions/` entry stating what it supersedes or revises

## Severity: warning

## Source: global decision journal

## Last triggered: never
