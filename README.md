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

Each artifact is updated by its own upstream mechanism — there's no tap-wide rule, and none of these files should be hand-edited:

- `go-udap` is generated and pushed by [GoReleaser](https://goreleaser.com/) from `yo61/go-udap`'s release workflow.
- `jobhound` is updated by `.github/workflows/bump-jobhound.yml` in this repo, triggered via `repository_dispatch` from `yo61/jobhound`'s release workflow.

Every push and PR runs `brew audit --strict --new` and `brew install` (+ `brew test` for formulae) against changed artifacts via `.github/workflows/audit.yaml`.

## License

MIT — see [`LICENSE`](LICENSE).
