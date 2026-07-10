## Decision: Make `bump-jobhound.yaml` self-healing against Homebrew's 24h release cooldown

Add a `schedule` trigger and a cooldown gate to `bump-jobhound.yaml`. On any
trigger the workflow resolves a target version (dispatch payload, workflow input,
or — for scheduled runs — the latest on PyPI), and gates the bump on the target
being (a) newer than the formula, (b) without an already-open `bump/*` branch,
and (c) older than Homebrew's 24h cooldown. If the version is still inside the
cooldown the run is a graceful no-op that defers to the next scheduled run.

Also add a `workflow_dispatch` input `skip_cooldown` as an emergency override.

## Context: {why this came up}

jobhound 0.17.0 was the first release to run through the bottle pipeline (0.16.0
predates it). The `bump-jobhound` run failed in `brew update-python-resources`:

```
pip install ... --uploaded-prior-to=<now-24h> jobhound==0.17.0
Unable to determine dependencies for "jobhound==0.17.0"
```

Homebrew hardcodes a release cooldown (`RELEASE_COOLDOWN_DAYS = 1`, no env
override) so `update-python-resources` ignores any PyPI upload younger than 24h —
"so resource resolution is less likely to pick a freshly compromised PyPI
release." Because `dispatch-homebrew` fires seconds after publish (it even waits
on the PyPI index to go *fast*), the brand-new release is always too fresh, and
the one-shot bump failed with no retry.

## Alternatives considered:

- **Bypass the wrapper unconditionally** (regenerate resources with uv/pip, which
  has no cooldown). Rejected as the default: it discards a supply-chain safeguard
  we value elsewhere (pnpm `minimumReleaseAge`, Dependabot cooldowns). Kept only
  as the `skip_cooldown` emergency lever.
- **Delay the dispatch 24h / manual re-run.** Rejected: manual toil, easy to
  forget; a scheduled retry automates the same wait.
- **Self-healing gate + schedule (chosen).** Honours Homebrew's cooldown, lands
  the bump automatically once the version is >24h old, and no-ops cheaply in
  between.

## Reasoning: {why this option won}

The default path stays safe-by-default (respects the 24h delay); the schedule
makes eventual success automatic without a dispatch; and `skip_cooldown` gives a
fast valve for shipping an urgent fix to jobhound itself — it skips
`update-python-resources` (the only cooldown-enforcing step) and reuses the
existing resource stanzas, valid because a jobhound-self patch does not change
the dependency set.

## Trade-offs accepted: {what you gave up}

- New formula (and bottles) lag a release by ~24-30h in the normal path. For
  urgency, `skip_cooldown` is the escape hatch.
- The schedule runs a cheap no-op (checkout + one PyPI query) several times a day.
- `skip_cooldown` cannot fix a *compromised dependency* (it reuses resources);
  that case needs a direct uv/pip re-resolve.

## Supersedes: none. Complements
[2026-07-10-pr-pull-head-sha-pin.md](2026-07-10-pr-pull-head-sha-pin.md).

## Follow-up

`bump-unifictl.yaml` uses the same `update-python-resources` pattern via
`repository_dispatch` with no schedule, so it will hit the identical cooldown
failure on unifictl's next release. Apply the same self-healing gate there.
