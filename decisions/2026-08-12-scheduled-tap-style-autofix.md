## Decision: Re-lint the tap on a daily schedule and open a signed autofix PR when `brew style --fix` can correct what it finds

Add `style.yaml`: a daily cron (plus `workflow_dispatch`) that runs
`brew style --fix Casks Formula`, opens a signed `style/autofix` PR via
`[[2026-07-13-signed-commits-via-api-drop-bypass]]`'s `commit-recipe-pr` action
when the sweep changes anything, and fails the run when offenses remain that
rubocop could not correct.

Generalise `commit-recipe-pr` from a single `file-path` to a `file-paths` list,
since a style sweep can touch more than one recipe. All three existing callers
(`bump.yaml`, `revbump.yaml`, `bump-go-udap.yaml`) pass one path and are updated
in place.

## Context

`brew style` lints the **whole tap**, not the PR diff. `tests.yaml` runs it via
`brew test-bot --only-tap-syntax` and is paths-filtered to `Formula/**` and
`Casks/**`. Those two facts combine badly:

1. A file can become non-compliant with no commit to this repo. Homebrew ships
   new and stricter cask cops regularly.
2. Nothing detects that until someone opens a PR touching a recipe — and then it
   fails **that** PR, which never touched the offending file.

This is not hypothetical. On 2026-08-11, PR #104 (an automated jobhound 0.18.0
bump) failed on both `macos-26` and `ubuntu-latest` with five
`Cask/StanzaOrder`/`Cask/StanzaGrouping` offenses in `Casks/go-udap.rb` — a file
the PR does not touch and which had passed `brew test-bot` unchanged on
2026-07-22 (`ee1cfb4`). Homebrew's cops changed in between (`2d7bd3d` adds
`on_macos`/`on_linux` to the cask stanza order, `0ac0cf4`, `15b6690`). Both jobs
died at the `Tap syntax` step, so neither reached `Build bottle`;
`publish-bottles.yaml` never fired and the bump could not land. Fixed manually in
#105.

Left alone, this recurs on every future cop change, and always lands on whichever
release bump happens to arrive next.

## Alternatives considered

- **Do nothing; fix by hand when a bump PR goes red.** Rejected: the cost falls
  on a release, at the least convenient moment, and the failure reads as "the
  bump is broken" rather than "the tap drifted".
- **Scope `brew style` to changed files in `tests.yaml`.** Rejected: it hides the
  rot rather than fixing it, and it diverges the tap's gate from what Homebrew's
  own `test-bot` checks. The tap really should be clean tap-wide.
- **Autofix on PR branches instead of on a schedule.** Rejected: pushing commits
  onto a contributor's (or a bot's) branch mid-review is intrusive, and it still
  detects nothing until a PR exists — the actual gap here.
- **Weekly instead of daily.** Rejected: a cop change could sit for up to seven
  days and still ambush a release bump, which is the exact scenario being fixed.
  The job is one `brew style` and exits clean on almost every run.
- **Duplicate the `createCommitOnBranch` logic inside `style.yaml`.** Rejected:
  that would be a fourth copy of the signing dance. Generalising the existing
  composite action to a path list is a smaller change than a second
  implementation.

## Reasoning

- **Signed PR, not a push.** `main`'s ruleset requires signatures and a PR, so the
  sweep uses the same `createCommitOnBranch` route as every other automated
  change here. A human still reviews the diff.
- **Fixed `style/autofix` branch, skipped when it already exists.** A run-scoped
  branch name would stack a new duplicate PR every day until the first one
  merged. Mirrors the "branch already exists; PR is already open" gate in
  `bump-go-udap.yaml`.
- **Open the PR *and* fail the run when leftovers remain.** `brew style --fix`
  can partially correct: the PR carries what was fixed, and a red run surfaces
  what was not, rather than one outcome masking the other.
- **Workspace-relative paths (`Casks Formula`), not the tap name.**
  `setup-homebrew` registers the checkout as the tap and hard-resets the tree;
  a relative path is unambiguously the copy the commit step reads. Same reason
  `bump-go-udap.yaml`'s "Normalise cask style" step uses one.
- **One mutation for all paths.** A multi-file sweep lands as a single commit
  rather than one commit per file.
- **Per-path fail-closed guard retained.** The action errors if *any* listed path
  is unchanged, preserving the existing single-path semantics exactly — a caller
  that silently produced no edit gets an error, not an empty PR.

## Trade-offs accepted

- Covers the rubocop half of the tap-syntax gate only. `brew style <tap>` also
  runs shellcheck and actionlint over `.github`; neither is autocorrectable, and
  workflow changes are already gated by `zizmor.yaml` and by `test-bot` on the
  next recipe PR. If actionlint rot ever bites, widen this then.
- A daily scheduled run that is a no-op ~365 days a year. The cost is one
  ubuntu-latest job; the alternative is finding out during a release.
- GoReleaser still renders the go-udap cask in the pre-cop-change shape. That is
  already handled at bump time by `bump-go-udap.yaml`'s `brew style --fix` step,
  so the sweep is a backstop for drift *between* releases, not a substitute for
  it.
- Autofix PRs need a human to merge them; nothing auto-merges `style/*` the way
  `publish-cask.yaml`/`publish-bottles.yaml` do for bumps. Deliberate — a
  rubocop autocorrection on a recipe deserves a look.

## Supersedes

Nothing. Extends `[[2026-07-13-signed-commits-via-api-drop-bypass]]` (the signed
commit route and the `commit-recipe-pr` action it introduced) and
`[[2026-07-21-cask-signed-release-flow]]` (the go-udap cask flow whose rendered
output this backstops).
