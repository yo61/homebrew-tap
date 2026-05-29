# yo61 Homebrew tap

Homebrew formulae and casks for tools published by [yo61](https://github.com/yo61).

## Install

```bash
brew install yo61/tap/<name>
```

For example:

```bash
brew install yo61/tap/jobhound   # formula
brew install yo61/tap/go-udap    # cask
```

## Available formulae

| Formula | Description |
| --- | --- |
| [`jobhound`](https://github.com/yo61/jobhound) | Action-based CLI for tracking a job hunt |

## Available casks

| Cask | Description |
| --- | --- |
| [`go-udap`](https://github.com/yo61/go-udap) | Squeezebox UDAP configuration tool |

## How content lands here

Different upstream mechanisms update different artifacts in this tap — none should be hand-edited:

- **Casks** are generated and pushed by [GoReleaser](https://goreleaser.com/) from the upstream project's release workflow (currently `go-udap`).
- **Formulae** are updated by per-formula GitHub Actions workflows in this repo, triggered via `repository_dispatch` from the upstream project's release workflow (currently `jobhound`, via `.github/workflows/bump-jobhound.yml`).

Every push and PR runs `brew audit --strict --new` and `brew install` (+ `brew test` for formulae) against changed artifacts via `.github/workflows/audit.yaml`.

## License

MIT — see [`LICENSE`](LICENSE).
