## Decision: Open bump PRs as drafts, and check on every formula change that the bottle block matches the formula version

`bump.yaml` and `revbump.yaml` open their `bump/*` PR as a draft.
`publish-bottles.yaml` marks it ready after it has committed the bottle block,
immediately before the squash-merge. A separate `bottle-block.yaml` workflow
runs `.github/scripts/check-bottle-blocks.sh`, which fails when a formula's
bottle `root_url` does not end in `<formula>-<version>[_<revision>]`.

## Context: why this came up

`brew install unifictl` 404ed for every user: `main` carried the 0.5.6 `url`
with the 0.5.5 bottle block. PR #130 was merged by hand at 14:23:10Z while
publish run 37019423691 was in its upload step (started 14:22:59Z, assets
created 14:23:35Z). The merge landed the bump commit without the bottle commit
and deleted the branch; the run's `createCommitOnBranch` then returned 404.
Repaired in #131.

Contributory factors:

- A bump PR is green and mergeable for about a minute between test-bot
  finishing and the publish run merging, and nothing on the page says it is one
  commit short.
- The ruleset requires 0 approvals and no status checks, and the admin role
  bypasses it.
- The Rust build dependency added the same day (#127) took test-bot from a few
  minutes to 18, lengthening the wait before that window.
- The already-bottled-on-main check (2026-09-13) passes on this path: `main` is
  not bottled when the run starts.
- A hand merge also preceded the 0.5.5 incident (#121/#122), through a
  different mechanism, so a control tied to one timing would not cover both.

## Alternatives considered:

- **Required status check in the ruleset.** Rejected for now: needs an
  infra-as-code change, and the admin bypass still permits the merge with one
  extra click. The check ships non-required and can be promoted later.
- **Draft PRs alone.** Stops the merge that happened, but says nothing about an
  unbottled formula reaching `main` by another route (a hand-edited fix PR).
- **Re-check that the PR is open immediately before uploading.** Rejected on
  2026-09-13 for the same reason it fails here: it narrows the race without
  closing it.
- **Put the check in `tests.yaml`.** Rejected: `publish-bottles.yaml` runs only
  when the `brew test-bot` workflow concludes successfully, so a job that is
  red on every unbottled bump PR would stop all publishing.

## Reasoning:

A draft cannot be merged by anyone, admin bypass included, so it removes the
window rather than narrowing it, with no ruleset change. Marking ready after
the bottle commit means that from the moment the PR becomes mergeable, a hand
merge lands the bottled formula. The check tests the invariant itself — what
`main` declares must be what the release serves — so it also goes red on `main`
if the state arrives some other way, instead of being found by a user.

## Trade-offs accepted:

- Every bump PR shows a red `bottle block` check until it is bottled. That is
  the intended signal, and the message says so.
- The check is not required, so it informs and does not block.
- If marking ready fails, the run stops after uploading, leaving a draft PR
  that already carries the bottle commit: marking it ready and merging by hand
  is safe at that point.
- `gh pr ready` with the release App's token is unverified until the next
  release exercises it.
- A person can still mark a draft ready and merge it early. That takes two
  deliberate actions instead of one.

## Supersedes: none — adds to 2026-09-13-bottle-content-invariant.md, whose
checks stay.
