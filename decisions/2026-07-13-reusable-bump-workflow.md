## Decision: Extract the two bump workflows into a reusable `bump.yaml`

Replace the ~95% duplicated `bump-jobhound.yaml` and `bump-unifictl.yaml` with a
single reusable workflow (`bump.yaml`, `on: workflow_call`) and two thin callers
that keep the per-formula triggers and pass three inputs: `formula`,
`package-name`, `exclude-packages` (plus `version`). Secrets are passed
explicitly, not inherited.

## Context

A `git diff` of the two bump files showed every difference was the formula name
or the two `update-python-resources` args (`--package-name`,
`--exclude-packages`). ~150 lines of identical gate/tap/awk/commit logic were
maintained twice, so any fix had to be applied in both.

Global CLAUDE.md's "no premature abstraction / rule of three" would normally
defer this until a third formula. Robin explicitly directed the extraction now,
which overrides that default for this change.

## Alternatives considered:

- **Leave duplicated until a third formula (rule of three).** The standing
  default; overridden by explicit direction.
- **Reusable `workflow_call` workflow (chosen).** Callers keep
  `repository_dispatch`/`workflow_dispatch` (a reusable workflow inherits the
  caller's `github.event`); the reusable file holds the logic once.
- **Composite action.** Rejected: composite actions can't own multi-step auth,
  token minting, or job-level permissions cleanly; a reusable workflow is the
  right unit for a whole job.

## Reasoning:

One copy of the logic, parameterised by three inputs that exactly capture the
observed differences. Two hardening improvements fell out:

- Secrets are declared under `on.workflow_call.secrets` and passed explicitly
  (only the two App-token secrets), replacing the originals' ambient
  `secrets.*` reads. `secrets: inherit` was rejected — zizmor flagged it as
  leaking all repo secrets into the reusable workflow.
- `contents: read` is set on both the caller job and the reusable job. A called
  workflow's `GITHUB_TOKEN` permissions are capped by the caller, so the caller
  must grant what the reusable job declares.

`version` is resolved in the caller as
`client_payload.version || github.event.inputs.version`; `||` returns the first
truthy operand (empty string is falsy), reproducing the old
`${DISPATCH:-${INPUT:-}}` fallback, and the reusable gate still regex-validates
it before any shell use.

## Trade-offs accepted:

- Not runtime-tested. `actionlint` and `zizmor` pass, but `workflow_call`
  resolution, explicit secret passing, and permission capping are only fully
  exercised by a real bump run. The first release bump is the true test.
- One more file to read to follow the full flow (the reusable workflow), against
  ~80 fewer total lines and a single source of truth for the logic.

## Supersedes: none. Refactors the workflows from
[2026-07-12-cooldown-bypass-flag.md](2026-07-12-cooldown-bypass-flag.md) without
changing their behaviour.
