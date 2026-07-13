## Decision: Gate `zizmor.yaml` on `.github/workflows/**` changes

Add a `paths` filter to both the `pull_request` and `push` triggers of
`zizmor.yaml` so the workflow-security scan only runs when a workflow file
changes.

## Context

zizmor only analyses `.github/workflows/**` (there are no `.github/actions/**`
or zizmor config files in this repo). But its triggers were unfiltered, so it
re-scanned an unchanged directory on the tap's dominant traffic: every `bump/*`
PR (which touches only `Formula/*.rb`) and every bottle commit
`publish-bottles.yaml` pushes to `main` (which adds only a `bottle do` block).
Those runs can only ever reproduce the previous result.

## Alternatives considered:

- **Leave triggers unfiltered (status quo).** Rejected: pure wasted CI on the
  majority of this repo's activity, for a scan whose inputs did not change.
- **`paths` filter (chosen).** zizmor runs only when a workflow/action file
  actually changes — which, by definition, is the only time it can find
  anything new. Adding a workflow file is itself a change under
  `.github/workflows/**`, so nothing escapes the filter.
- **`paths-ignore` inversion / always-run stub.** Rejected as unnecessary: those
  patterns exist to keep a *required* status check reporting on every PR. Not
  needed here (see Reasoning).

## Reasoning:

Verified against `main`'s ruleset before choosing: it enforces `deletion`,
`required_signatures`, `pull_request`, and `non_fast_forward` but **no required
status checks**, and the publish pipeline gates on the `brew test-bot`
`workflow_run` — never on zizmor. So a skipped zizmor run cannot leave a PR
pending-forever or block the bottle pipeline. The `paths` filter is therefore
both safe and the simplest correct option.

## Trade-offs accepted:

If zizmor is ever made a *required* status check, the `paths` filter would cause
it to report "skipped" (pending) on PRs that touch no workflow file, blocking
merge. At that point switch to an always-run stub or `paths-ignore` inversion.
Documented here so the trade-off is a conscious one.

## Supersedes: none.
