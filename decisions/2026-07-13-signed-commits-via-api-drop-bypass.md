## Decision: Create bump + bottle commits via the GitHub API so `main` is fully signed, and land them by merging the PR (not pushing to `main`)

Replace the two local `git commit` + direct-`push`-to-`main` steps with GitHub
GraphQL `createCommitOnBranch` commit creation, and land the bump PR by calling
the merge API with the `squash` method. Every commit that reaches `main` is then
signed by GitHub (`verified`), and nothing pushes to `main` outside a PR. This
removes the tap's dependency on the ruleset's `always`-bypass App actor, which is
removed separately in infra-as-code.

**Signing mechanism — verified empirically (2026-07-13):** a commit created by
`createCommitOnBranch` returns `verified=true, reason=valid, committer=GitHub`;
the same file created via the REST Contents API (`PUT /contents`) returns
`verified=false, reason=unsigned`. Only `createCommitOnBranch` (and the web UI)
have GitHub build and sign the commit server-side. This is the same GraphQL
"signing dance" the pre-2026-07-10 bump workflow used and the bottling
simplification removed in favour of the bypass.

## Context

`main`'s `Default Branch` ruleset (`id 16783297`) enforces four rules:
`deletion`, `required_signatures`, `pull_request` (0 approvals), and
`non_fast_forward`. Today a single `Integration` bypass actor (`actor_id
3654569`, the `SEMANTIC_RELEASE_APP`, `bypass_mode: always`) exempts the release
App from all four, which is the only reason the current flow works:

- `bump.yaml` creates the bump commit with a plain local `git commit` (unsigned)
  and pushes a `bump/*` branch.
- `publish-bottles.yaml` runs `brew pr-upload` (which adds the bottle block and
  commits locally, also unsigned), `git rebase`s onto `main`, and
  `git push HEAD:main` — a **direct push** of **unsigned** commits.

Both only succeed because the App bypasses `required_signatures` and
`pull_request`. Consequences:

1. Every bump/bottle commit on `main` is `verified=false, reason=unsigned` (e.g.
   `b1126fb`, `bd5ce42`, `fa88bb3`). A ruleset that demands signatures is
   satisfied only by an ever-present bypass — a standing contradiction.
2. Every bump PR shows **"Merging is blocked — Commits must have verified
   signatures"** because its commit is unsigned. This is cosmetic (the PR never
   merges via the button; the App direct-pushes) but it repeatedly reads as a
   broken release — it is what prompted this work (unifictl 0.4.0, PR #83).
3. The `Close the bump PR` step in `publish-bottles.yaml` fails on most runs:
   the direct push content-merges the PR and auto-deletes the branch, but a
   racy `gh pr list --state open` still returns the PR, so `gh pr close
   --delete-branch` runs and 404s on the already-deleted branch (`exit 1`).
   `publish-bottles` therefore reports red on successful releases.

The load-bearing constraint discovered while designing the fix: **dropping the
bypass makes a direct push to `main` illegal under the `pull_request` rule, not
just `required_signatures`.** And `git rebase` always produces new *unsigned*
local commits. So a signed, bypass-free `main` cannot be reached by pushing to
`main` at all — the change must land by *merging the PR*, and every commit on the
branch must be created via the API (GitHub signs API-authored commits with its
web-flow key; local `git commit` cannot be signed without a provisioned key).

## Alternatives considered

- **Keep the bypass; do nothing.** Rejected: leaves the contradiction, the
  permanent scary banner, and the red-on-success CI. Robin chose the clean
  end-state (fully signed `main`, no bypass).
- **Sign only the bump commit; keep bypass for the bottle commit.** Rejected:
  `main` history stays mixed and the bypass stays load-bearing — partial work,
  little payoff.
- **Provision a GPG/SSH signing key in CI and keep `git commit` + local push.**
  Rejected: adds a long-lived secret to manage/rotate, and a direct push to
  `main` still violates the `pull_request` rule once the bypass is gone.
  `createCommitOnBranch` needs no key (GitHub signs) and routes through a PR
  merge by construction.
- **Create the commits via the REST Contents API (`PUT /contents`).** Rejected:
  probed and confirmed it does *not* sign (`reason=unsigned`); only
  `createCommitOnBranch` and the web UI do.
- **Squash-merge unsigned branch commits (GitHub signs the squash result).**
  Rejected as the *sole* mechanism: it might satisfy `required_signatures` on
  `main`, but the pre-merge PR banner behaviour with unsigned branch commits is
  not something to rely on, and it leaves the bump PR looking blocked. Signing
  both branch commits removes all ambiguity and clears the banner. Squash is
  still the merge method (see below); we just don't lean on it to launder
  signatures.

## Reasoning

- **`createCommitOnBranch` for both commits.** Each step changes exactly one
  file (`Formula/<f>.rb`), passed as a single base64 `additions` entry.
  `bump.yaml`: create `refs/heads/bump/<f>-<v>` at `main` HEAD (REST — refs need
  no signing), then run the mutation with `expectedHeadOid=main` HEAD.
  `publish-bottles.yaml`: after `pr-upload` produces the bottled formula content
  (and uploads bottles to the Release), run the mutation on the `bump/*` branch
  with `expectedHeadOid=`branch head. Both commits land signed; the PR shows two
  verified commits and no block banner.
- **Merge via `PUT /pulls/{n}/merge`, `merge_method=squash`.** Satisfies the
  `pull_request` rule (it *is* a PR merge) with 0 required approvals, and the
  squash commit is GitHub-signed — so `required_signatures` passes with no
  bypass. Squash gives one clean signed commit per release on `main`. Pass the
  bottle commit `sha` to the merge call so it fails closed if the head moved
  (preserves the TOCTOU protection from
  `[[2026-07-10-pr-pull-head-sha-pin]]`).
- **Delete the manual push and the racy close.** The merge API auto-closes the
  PR; a best-effort `DELETE /git/refs/heads/<branch>` (ignoring 404) replaces the
  whole `Close the bump PR` step. This also fixes consequence (3) — the
  red-on-success bug — as a side effect. The duplicate-`Authorization`-header
  git workaround and the fetch/rebase disappear with the direct push.
- **Staged rollout keeps a safety net during the switch.** Ship the signed-commit
  workflows *while the bypass is still present* (harmless when unneeded), verify
  the next real release lands `verified` and merges cleanly, and only then remove
  the bypass actor in infra-as-code. A signing bug thus cannot brick the release
  pipeline with no fallback.

## Trade-offs accepted

- The bottle bottling still runs `brew pr-upload` for its Release upload + formula
  edit; we discard its local commit and re-author the content via the API. Minor
  redundancy (one throwaway local commit) bought for a signed result.
- Squash discards the individual bump/bottle commits from `main`'s history (they
  remain on the closed PR). Accepted for a clean one-commit-per-release `main`.
- Bump PRs will show **closed-by-merge** with a squash commit rather than the
  previous content-merge; functionally identical, and now genuinely "merged".
- `createCommitOnBranch` is optimistic-concurrency (`expectedHeadOid`); a
  concurrent release of the *same* formula would fail closed. Same-formula
  releases are serialized upstream, and concurrent *different*-formula releases
  touch different files and branches, so this is a fail-closed guard, not a real
  hazard.

## Supersedes

Evolves `docs/superpowers/specs/2026-07-10-homebrew-bottling-and-bump-simplification-design.md`
("Why the signing dance disappears", lines 172-187), which deliberately relied on
the `always`-bypass App to push unsigned commits to `main`. That reliance is now
removed. Builds on `[[2026-07-10-pr-pull-head-sha-pin]]` (head-sha TOCTOU) and
`[[2026-07-13-reusable-bump-workflow]]` (the reusable `bump.yaml` this edits).
