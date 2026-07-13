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
