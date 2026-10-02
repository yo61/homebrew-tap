## Decision: Python formulae carry `depends_on "rust" => :build` when a resource's build backend is `uv_build`

`Formula/jobhound.rb` and `Formula/unifictl.rb` declare Rust as a build-only
dependency. The brewed runtime deps (`cryptography`, `pydantic`, `rpds-py` via
`=> :no_linkage` + `pypi_packages exclude_packages`) stay as they are.

## Context: why this came up

The jobhound 0.18.5 bump (PR #126, run 36998464170) failed `brew test-bot` on
both platforms with `error: can't find Rust compiler`. `xdg-base-dirs` 6.0.3
changed its build backend from `poetry-core` to `uv_build>=0.7.19,<0.13`.
Homebrew's `std_pip_args` passes `--no-binary=:all:`, so pip builds the backend
from sdist inside its isolated build environment; `uv_build`'s sdist requires
`maturin`, whose sdist requires a Rust compiler.

## Alternatives considered:

- **Brewed formula + `exclude_packages`** (the PR #10 pattern). Not available:
  that pattern replaces a runtime package with a homebrew-core keg. The Rust
  need here is in a build backend pip fetches into its own overlay, and no
  homebrew-core formula provides `uv_build` as a Python module.
- **Pin `xdg-base-dirs` to 6.0.2 upstream.** Needs a release of each affected
  project and only defers the failure until another dependency adopts
  `uv_build`.
- **Disable build isolation and supply the backend another way.** Diverges from
  `virtualenv_install_with_resources` for one resource.

## Reasoning:

homebrew-core does exactly this: `barman` (`# for uv_build > maturin`),
`mail-deduplicate` (`# for click_extra > uv_build`) and `mcp-atlassian`
(`# for py_key_value_aio > uv_build > maturin`, alongside
`cryptography => :no_linkage`). A build-only dependency is not recorded in the
bottle, so it costs CI time and nothing at install time for anyone pouring a
bottle. unifictl gets the same line because it vendors `xdg-base-dirs` too and
its next bump would fail identically.

## Trade-offs accepted:

- Bottle builds compile `maturin` and `uv_build` from source — slower CI.
- A build from source (no bottle for the platform) now installs Rust.
- Partly reverses PR #10 (`0fc76d1`), which removed `rust => :build` from
  jobhound. Its goal — no Rust for bottle users, no Rust-built runtime deps in
  the venv — still holds.

## Supersedes: none
