## Decision: Land the go-udap cask via a signed bump PR, like the formulae — GoReleaser generates, the tap lands

Migrate the go-udap **cask** off GoReleaser's direct push to `main` (blocked
since the `Default Branch` ruleset's App bypass was removed on 2026-07-14) onto
the same signed-PR flow the formulae use. GoReleaser keeps rendering the cask but
attaches it to the go-udap release instead of pushing it; go-udap fires a
`repository_dispatch (bump-go-udap)`; a tap-side `bump-go-udap.yaml` fetches the
rendered cask, commits it to `Casks/go-udap.rb` via `createCommitOnBranch`
(GitHub-signed), and opens a `cask/go-udap-<v>` PR; `publish-cask.yaml`
squash-merges it once `tests.yaml` is green.

## Context

go-udap was the only artifact still on the pre-bypass-removal direct-push path.
Every go-udap release since 2026-07-14 (v2.4.4, v2.4.5) fails at the cask push
with `409 Repository rule violations found` (needs a PR; needs verified
signatures). Formulae already moved to the signed flow in
[[2026-07-13-signed-commits-via-api-drop-bypass]].

## Alternatives considered

- **Re-add the App as a ruleset bypass actor.** Rejected: reverses
  [[2026-07-13-signed-commits-via-api-drop-bypass]] deliberately.
- **Tap owns a hand-maintained cask, edited in place.** Rejected: copies the
  cask's derived manpage/completion list into the tap where it can drift from
  go-udap's actual subcommand set, needing a downstream online-audit special
  case. Generating from the build makes drift structurally impossible.
- **GoReleaser opens the PR itself.** Rejected: its branch commit is unsigned
  and would lean on squash-merge to launder the signature — the mechanism this
  tap already declined.

## Reasoning

Split by what each repo authoritatively knows: go-udap owns cask *generation*
(where the subcommand set lives), the tap owns *landing* (where main's signature
protection lives). GoReleaser never touches the tap — it only emits an artifact.
Reuses the existing signing dance via a generalized `commit-recipe-pr` action;
adds a `cask/` branch prefix so `publish-bottles.yaml` (guarded on `bump/`) is
untouched.

## Trade-offs accepted

- go-udap stays in the cask-generation business (GoReleaser), against an earlier
  "delete homebrew_casks entirely" idea — but only generation; the broken push
  is gone.
- One more merge workflow (`publish-cask.yaml`) alongside `publish-bottles.yaml`,
  kept separate rather than branching the bottle-specific one.

## Supersedes

Builds on [[2026-07-13-signed-commits-via-api-drop-bypass]] and
[[2026-07-10-pr-pull-head-sha-pin]] (the head-sha TOCTOU merge pin reused by
publish-cask). Design spec:
go-udap `docs/superpowers/specs/2026-07-21-homebrew-cask-signed-release-flow-design.md`.
