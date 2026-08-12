## Decision: Replace only the bottle assets a publish run is uploading, and stop the run before it mutates anything when there is no open bump PR

`publish-bottles.yaml` clears pre-existing release assets by exact filename,
read from the bottle JSON test-bot produced (`.[].bottle.tags[].filename`),
instead of deleting every `*.bottle.tar.gz` on the version's release. A new
`guard` job resolves the open bump PR before the publish job starts, so a run
with nothing to publish skips rather than discovering that after uploading.

## Context: why this came up

`brew upgrade jobhound` 0.18.1 404'd for every user: the formula on `main`
declared rebuild 0 bottles, while the release held only rebuild 1 assets.

The publish flow re-triggers itself. The publish job pushes the bottle commit to
the bump PR's branch; that is a `synchronize`, which runs test-bot again, whose
completion fires this workflow a second time. On 0.18.1 that produced three
publish runs:

1. Uploaded rebuild 0 bottles and failed to merge — the ruleset requires an
   approving review, and the reviewing App got to the PR 39s after the commit,
   five seconds after the 5 x 5s retry window gave up.
2. Fired from the bottle commit's test-bot, re-uploaded rebuild 0, merged. The
   formula on `main` was correct and installable at this point.
3. Fired from *its* bottle commit's test-bot, minutes after the merge. It
   deleted the live rebuild 0 assets, uploaded rebuild 1 (test-bot bumps the
   rebuild once the version is already bottled on `main`, which changes the
   filenames), and only then failed on the deleted branch.

Run 3's deletion is what broke installs. The suffix-scoped clearing came from
\#107, which fixed a real problem — pr-upload aborts on `ReleaseAsset
already_exists`, stranding \#104's retry — but scoped the deletion to the
version rather than to the assets being replaced. Within a version, the rebuild
number is part of the filename, so "this version's bottles" includes bottles a
published formula is serving.

## Alternatives considered:

- **Revert #107 and accept unre-runnable publishes.** Rejected: brings back the
  stranded-retry failure it fixed, which needed manual repair too.
- **Keep the suffix deletion, add the guard only.** Rejected: the guard closes
  the path that fired, not the hazard. Any future duplicate or manual run would
  still delete live bottles, and the failure is invisible until a user installs.
- **Keep the deletion scoped to filenames, no guard.** Rejected: a post-merge
  run would still download artifacts, re-upload a rebuild nothing references,
  and fail loudly at the end. Correct, but noisy and wasteful.
- **Suppress the self-retrigger in `tests.yaml`.** Rejected for now: skipping
  test-bot by commit message is fragile, and the wasted run is cheap once the
  guard makes it a no-op.

## Reasoning:

The invariant that matters is that the bottle block on `main` always points at
assets that exist. Deleting only what this run is about to re-upload makes that
invariant impossible to break by deletion: an asset is removed only when the
same name is written back seconds later, or the run fails and the formula on
`main` is not touched. The guard then removes the case that has no business
uploading at all. The two are independent — either alone leaves a hole.

Widening the merge retry to 20 x 15s addresses the third factor: the first
publish attempt failing on a slow approval is what makes a second cycle routine
rather than exceptional.

## Trade-offs accepted:

- A failed publish can leave one orphan set of assets on the release if a later
  run bottles a different rebuild. Harmless (nothing references them) and
  visible on the release page, where the old behaviour's mistake was invisible.
- A merge blocked for more than 5 minutes now costs a 5-minute job before it
  fails, instead of 25 seconds.
- The guard adds a job start (~10s) to every publish.

## Supersedes: none — revises the asset-clearing behaviour added in #107
(`fix(ci): make the bottle upload re-runnable`), which had no decision record.
