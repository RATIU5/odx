# Changelog

All notable changes to odx are listed here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com). A release supports one rule set and one compiler, and `odx --version` prints all three.

| Release | Rule set | Compiler                      |
| ------- | -------- | ----------------------------- |
| 0.4.0   | 2        | `dev-2026-10-nightly:84bc3fc` |
| 0.3.0   | 2        | `dev-2026-10-nightly:84bc3fc` |
| 0.2.0   | 2        | `dev-2026-10-nightly:84bc3fc` |
| 0.1.0   | 1        | `dev-2026-09-nightly:a2fb372` |

A project on `dev-2026-09` stays on odx 0.1.0.

## 0.4.0

Your findings, messages, exit codes and JSON keys are the same as in 0.3.0. Upgrading needs no change to `odx.json`; set `"github:RATIU5/odx"` to `0.4.0` in `mise.toml`. The 0.2.0 and 0.3.0 releases carry no download, so install 0.4.0 or later.

### Added

- The release carries a build of `odx` and `odinfmt` for Linux on amd64 beside the one for macOS on arm64. It needs glibc 2.34 or newer, so it runs on Ubuntu 22.04 and later.
- CI runs every gate on Linux as well as macOS.

## 0.3.0

Your findings, messages, exit codes and existing JSON keys are the same as in 0.2.0. Upgrading needs no change to `odx.json`; set `"github:RATIU5/odx"` to `0.3.0` in `mise.toml`.

### Added

- `odx rules` lists each rule and why it exists. `odx explain <rule>` also says how to fix it. Both take `--json` and need no repo, no `odx.json` and no `odin` on `PATH`.
- `odx check --max-findings N` prints only the first N finding lines and says so on stderr. It can't be combined with `--json`.
- The `--json` summary lists the `targets` odx compiles for.
- `odx --help` lists every error code and says what `odx --version` guarantees.

### Changed

- `odx check` is much faster on repos with many directories and long `exclude_dirs`, `vendored` or `pending` lists. A test repo with 4000 directories and 3000 listed ones went from 4.4 s to 0.2 s.
- The README is shorter. The rest of the behavior is in `docs/reference.md`.
- odx asks the compiler for at most 10000 errors per package and target, where it asked for a million. A package with more compile errors than that has the rest left out.

### Fixed

- A file tag such as `#+vet` after the `package` line no longer ends the run with a `compiler-output` timeout. The compiler loops on it for minutes when asked for a million errors.
- A collection path that is a FIFO no longer hangs odx on Linux.

## 0.2.0

Moves to the `dev-2026-10` compiler and rule set 2. The rules are the same 24, but `format` and `parse-unsupported` results come from a printer and a parser built with the new compiler, so some code can get new findings.

### Changed

- Needs the compiler `dev-2026-10-nightly:84bc3fc`.
- Refuses an `odx.json` with `"version": 1`. To upgrade, raise `version` to 2 and `odin` to the new compiler in the same commit as the `mise.toml` change, then fix new findings or list their packages under `pending`.

## 0.1.0

First release, for the compiler `dev-2026-09-nightly:a2fb372`.

### Added

- `odx check` with `--json` and `--pending`, `odx init`, `--help` and `--version`.
- 24 rules for format, naming and syntax, ignores, `pending` packages and `vendored` trees.
- Formatting checked against the vendored OLS printer.
- Every package checked for `darwin_arm64` and `linux_amd64`.
- Release builds for macOS on arm64.
