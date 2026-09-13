## Decision: Refuse to publish a version that is already bottled on main, and verify the baked root_url matches the string that check greps for

`publish-bottles.yaml` reads `Formula/<formula>.rb` from `main` before it
deletes or uploads anything, and aborts when that formula already carries the
`root_url` this run is about to bake in. After `pr-upload`, it also asserts the
root_url brew actually wrote equals that same string, so the check above cannot
fail open unnoticed.

## Context: why this came up

`brew install unifictl` 0.5.5 failed the bottle integrity check for every user:
the formula on `main` declared `1c6a79e6`/`7ee8ff81`, the release served
`e5c3e544`/`4ca66eb9`.

Two publish runs bottled 0.5.5. Run 34625912156 uploaded test-bot 34625079863's
bottles and committed their checksums as 5827c0c1; its squash-merge then failed
because the required approving review never arrived inside the 20 x 15s window.
The PR was approved and merged by hand at 17:17:34. Run 34626799039 had passed
its guard at 17:17:05 — 29s before that merge — downloaded test-bot
34626023523's separate build, deleted the live assets at 17:18:03, uploaded its
own, and died at 17:18:09 on the branch the merge had removed.

The 2026-08-12 decision scoped asset deletion to the exact filenames a run is
uploading, on the reasoning that a second build carries a different rebuild
number and therefore a different filename. That holds only once the version is
bottled on `main`, which is what makes test-bot bump the rebuild. Run 2's
test-bot started before the merge, so `main` was not yet bottled, the rebuild
stayed 0, and the filenames matched exactly. Filename scoping gave no
protection at all on this path.

The deeper gap is that its safety argument — "an asset is removed only when the
same name is written back seconds later" — is an argument about existence.
Bottles are not byte-reproducible, so the name written back carries different
bytes, and the invariant that actually matters is not "the bottle block on main
points at assets that exist" but "points at assets that hash to what it
declares".

## Alternatives considered:

- **Re-resolve the open bump PR immediately before the destructive step.**
  Rejected: it narrows the race from ~60s to a few seconds without closing it,
  and it keeps trusting a signal that is stale the instant it is read. The PR
  being open is a proxy; what the run needs to know is whether `main` is
  serving these assets.
- **Verify checksums after uploading and fail the run on a mismatch.** Rejected
  as the primary control, and offered as an alternative: it detects the
  corruption instead of preventing it, so the window where installs fail still
  opens, and the run that detects it is the run that caused it. Attractive as a
  belt-and-braces addition later; it catches causes this check does not
  anticipate.
- **Make run 1 merge reliably so no second cycle exists.** Rejected as the
  whole answer for the reason the 2026-08-12 decision rejected a guard-only
  fix: it closes the path that fired, not the hazard. A manual re-run or a
  duplicate would still reach the delete-and-upload. Worth doing on its own
  merits — the missing approval is a real contributory factor and still
  unaddressed.
- **Suppress test-bot on the bottle commit.** Rejected again, for the reason
  already recorded: skipping by commit message is fragile.
- **Key the check on the release tag's assets rather than on main.** Rejected:
  the assets on a release are exactly what a racing run is about to change, so
  reading them answers the wrong question. `main` is the only source that
  states what users are actually installing.

## Reasoning:

`main` cannot race. Once the bottled formula is on `main` those assets are
live, whoever merged it and whenever — so a check against `main` is correct at
the moment of the mutation rather than at the moment some earlier job looked.
That is precisely the property the `guard` job lacks, and no amount of moving
the guard closer to the upload can give it.

Keying on the exact `root_url` string the run is about to bake means the check
and the upload cannot disagree about what "this version" means. `pkg_version`
carries any Homebrew `revision` and the release tag carries it too
(`unifictl-0.4.0_2` exists), so a revision bump targets its own release and is
not blocked, while a republish of the same pkg_version is. #104's retry keeps
working: a publish that failed before merging leaves `main` unbottled, so the
check passes and the re-run proceeds.

The post-upload root_url assertion exists because the check is a string match
against output brew produces. If brew ever bakes a different root_url the check
stops matching and fails open — silently, on the one path that protects live
bottles. Asserting the two agree turns that from a silent hole into a failed
run.

## Trade-offs accepted:

- A genuine rebuild publish (same pkg_version, higher rebuild number) is now
  blocked. There is no deliberate flow that produces one — test-bot only bumps
  the rebuild when `main` is already bottled, which in this pipeline happens
  only on the spurious self-retrigger — so this blocks the bad case and no
  known good one. Shipping a real rebuild would need a deliberate override.
- Repairing a release whose assets are missing while `main` is bottled (the
  0.18.1 shape) now requires an override too. That repair was manual anyway,
  and failing closed is the right default for it.
- One extra API call per publish, on a path that already makes several.
- The check reads `main` through the Contents API rather than the checkout,
  which is one more thing that can fail transiently. It fails the run rather
  than skipping, so a rate limit costs a re-run instead of a corrupted release.

## Supersedes: none — revises the asset-clearing behaviour recorded in
2026-08-12-bottle-asset-replacement-scope.md, whose filename scoping and
`guard` job both stay. That decision's invariant ("points at assets that
exist") is tightened here to "points at assets that match".
