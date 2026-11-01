# odx

> [!WARNING]
> This project is written with AI (Claude), as a proof of concept. I built it to see whether it is any use to me. Use it at your own risk.

## What it is

A strict, opinionated checker for Odin projects. `odx check` runs the compiler with pinned strict flags, then applies rules for format, naming and syntax. It prints one finding per line and exits 0 for none, 1 for findings and 2 for an error. Memory-checked tests and runs are planned.

## Why

I want one standard for Odin code that a team can't argue its way out of: no rule settings, no severities, no plugins. The compiler and the printer are pinned, so the same code gives the same result on every machine. Terms are in [GLOSSARY.md](docs/GLOSSARY.md), the principles in [docs/adr/0004-principles.md](docs/adr/0004-principles.md).

## Get started

odx installs through [mise](https://mise.jdx.dev), beside the compiler a project pins. A release carries `odx` and `odinfmt` for macOS on arm64 only. On Linux, build odx from source (see Develop). Add both lines to the project's `mise.toml`:

```toml
[tools]
odin = "dev-2026-10"
"github:RATIU5/odx" = "0.3.0"
```

If the repository is private, mise needs a GitHub token that can read it, set as `MISE_GITHUB_TOKEN`.

Then, in your repo:

```sh
mise install
odx init     # writes odx.json and odinfmt.json, and lists failing packages as pending
odx check
```

Commit `odx.json` and `odinfmt.json`. Format code with an `odinfmt` built from OLS commit `dd0f85d31c91e9d04202cc422288d15b52206474`, which reads the `odinfmt.json`:

```sh
git clone https://github.com/DanielGavin/ols
cd ols
git checkout dd0f85d31c91e9d04202cc422288d15b52206474
./odinfmt.sh   # builds ./odinfmt with the odin on PATH, which must be the pinned compiler
```

Useful commands: `odx --help`, `odx rules`, `odx explain <rule>`. The rest of the behavior, such as `odx.json`, ignores and output, is in [docs/reference.md](docs/reference.md). Release notes are in [CHANGELOG.md](CHANGELOG.md).

## Develop

```sh
mise install
mise run build     # build/odx, the debug build the tests use
mise run fmt       # format odx's sources with the vendored printer
mise run test
mise run golden    # the cases in tests/golden against build/odx
mise run self      # odx check on odx's own sources
mise run release   # build/release/odx
```

`mise tasks` lists the rest, such as `selection`, `e2e` and `dist`. CI runs the build, test, golden and self tasks on every pull request. A release is built by the manual release workflow, which creates a draft release `v<release>`. Raise `RELEASE` in `odx/rules.odin` first.
