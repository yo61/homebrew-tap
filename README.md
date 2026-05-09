# yo61 Homebrew tap

Homebrew formulas for tools published by [yo61](https://github.com/yo61).

## Install

```bash
brew install yo61/tap/<formula-name>
```

For example:

```bash
brew install yo61/tap/go-udap
```

## Available formulas

| Formula | Description |
| --- | --- |
| [`go-udap`](https://github.com/yo61/go-udap) | Squeezebox UDAP configuration tool |

## How formulas land here

Formulas in this tap are generated and pushed automatically by [GoReleaser](https://goreleaser.com/) from the upstream project's release workflow. Don't hand-edit files under `Formula/` — your changes will be overwritten on the next upstream release.

Every push and PR runs `brew audit --strict --new` and `brew test` against each formula via `.github/workflows/audit.yaml`.

## License

MIT — see [`LICENSE`](LICENSE).
