# yo61 Homebrew tap

Homebrew formulae and casks for tools published by [yo61](https://github.com/yo61).

## Install

```bash
brew tap yo61/tap
brew trust yo61/tap        # required: Homebrew ignores untrusted third-party taps
brew install yo61/tap/<name>
```

For example:

```bash
brew install yo61/tap/jobhound   # formula
brew install yo61/tap/go-udap    # cask
```

> [!NOTE]
> Recent Homebrew ignores formulae and casks from untrusted third-party taps
> until you trust them. If `brew install` reports the tap is not trusted, run
> `brew trust yo61/tap` (whole tap) or `brew trust --formula yo61/tap/<name>`
> (single formula) and re-run the install. See
> [Tap Trust](https://docs.brew.sh/Tap-Trust).

## Available formulae

| Formula | Description |
| --- | --- |
| [`jobhound`](https://github.com/yo61/jobhound) | Action-based CLI for tracking a job hunt |
| [`unifictl`](https://github.com/yo61/unifictl) | Imperative UniFi homelab actions beyond the Integration API |

## Available casks

| Cask | Description |
| --- | --- |
| [`go-udap`](https://github.com/yo61/go-udap) | Squeezebox UDAP configuration tool |

## How content lands here

Each artifact is updated by its own upstream mechanism — there's no tap-wide rule, and none of these files should be hand-edited:

- `go-udap` is generated and pushed by [GoReleaser](https://goreleaser.com/) from `yo61/go-udap`'s release workflow.
- `jobhound` and `unifictl` are updated by `.github/workflows/bump-jobhound.yaml` / `bump-unifictl.yaml`, triggered via `repository_dispatch` from each tool's release workflow. Each bump opens a PR that regenerates the formula with `brew bump-formula-pr` + `brew update-python-resources`.

Formula PRs are audited, installed, tested, and bottled across macOS (Apple Silicon + Intel) and Linux by `.github/workflows/tests.yaml` (`brew test-bot`). When that run is green on a `bump/*` PR, `.github/workflows/publish-bottles.yaml` runs `brew pr-pull` to attach the bottles to a GitHub Release and land the formula on `main`, so `brew install` pours a pre-built bottle instead of building from source.

## License

MIT — see [`LICENSE`](LICENSE).
