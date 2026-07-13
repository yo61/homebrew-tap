## Decision: Bump immediately using Homebrew's `--ignore-main-package-cooldown` instead of the self-healing cooldown gate

Replace the cooldown workaround in `bump-jobhound.yaml` and `bump-unifictl.yaml`
with a single immediate-bump path that resolves resources via
`brew update-python-resources --ignore-main-package-cooldown`. Delete the 24h
cooldown gate, the `schedule` catch-up trigger, and the `skip_cooldown`
emergency input. Bumps now land within minutes of a PyPI publish.

The flag shipped upstream in Homebrew/brew#23072 (merged 2026-07-13, commit
`76ca8d74`), so both workflows call it directly on the Homebrew that
`Homebrew/actions/setup-homebrew` provides — no fork pin. It requires Homebrew
from 2026-07-13 or later.

## Context

The retry design (superseded below) worked around Homebrew's 24h release
cooldown by waiting it out: a bump inside the cooldown deferred and a `schedule`
retried until the release was >24h old, with a `skip_cooldown` lever that shipped
url/sha only and reused stale resource stanzas. It cost every release a 24-30h
bottle lag, and `skip_cooldown` could not handle a release whose dependency set
changed (it re-used old stanzas).

The upstream flag removes the reason the workaround existed. It exempts the
formula's *own* package from the cooldown — passed to pip as a PEP 508
`name[extras] @ <sdist url>` direct reference, which bypasses pip's index
upload-time filter — while every dependency stays index-resolved and cooled. So
a fresh release resolves immediately *and* re-resolves dependencies safely,
which `skip_cooldown` never did.

Two findings shaped the workflow rewrite:

- `brew bump-formula-pr` calls `update_python_resources!` internally and has no
  flag to skip it, so it trips the cooldown independently. The workflows
  therefore set the top-level url/sha256 with the existing `awk` edit (from the
  old `skip_cooldown` path) and call standalone `update-python-resources` with
  the flag — `bump-formula-pr` is no longer used.
- jobhound resolves the `[mcp]` extra, whose deps (`mcp`, `starlette`,
  `uvicorn`, `sse-starlette`, `httpx-sse`, `anyio`, …) are vendored. The flag
  preserves extras on the direct-URL reference, so `--package-name "jobhound[mcp]"`
  still resolves them. unifictl is pure with no extras.

## Alternatives considered

- **Keep the gate as a fallback** (add the flag but retain the 24h defer/schedule
  so a brew or flag failure degrades gracefully). Rejected: more complexity than
  the simplification is worth, and the flag's failure mode is already safe.
- **Wait for the upstream PR to merge before adopting.** The workflows were
  first written against a fork pin so the benefit landed immediately; the PR
  merged the next day, so they now call plain upstream brew with no pin.
- **Add the flag to `bump-formula-pr` upstream too.** Out of scope for the agreed
  PR (maintainer scoped it to `update-python-resources`); the awk + standalone
  call avoids needing it.

## Reasoning

Immediate, safe bumps with far less workflow code (net ~100 fewer lines across
the two files). The dependency cooldown — the part that actually protects against
a compromised upstream — is fully retained.

## Trade-offs accepted

- Both workflows require Homebrew from 2026-07-13 or later (when the flag
  merged). `Homebrew/actions/setup-homebrew` provides current Homebrew, so this
  is satisfied in practice.
- Dropping the `schedule` removes auto-retry. If a bump fails — e.g. this release
  adds a dependency that was itself published <24h ago and is correctly still
  cooled, or a transient error — the run goes red and must be re-run via
  `workflow_dispatch`. This is rarer than the 24h lag it removes, and a loud
  failure on a genuinely-fresh dependency is the correct signal.

## Supersedes

- `decisions/2026-07-10-jobhound-bump-cooldown-retry.md` (this repo)
- `decisions/2026-07-10-homebrew-bump-cooldown-gotcha.md` (yo61/unifictl)
