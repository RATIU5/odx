# ols_printer

OLS's Odin printer, vendored for odx's `format` rule (`docs/adr/0003-vendored-ols-formatter.md`).

| | |
| --- | --- |
| Source | `src/odin/printer/{document,printer,visit}.odin` from <https://github.com/DanielGavin/ols> |
| OLS commit | `dd0f85d31c91e9d04202cc422288d15b52206474` |
| Compiler odx builds it with | `dev-2026-09-nightly:a2fb372` |
| License | MIT, in `LICENSE` |

## Local changes

The files are upstream's, byte for byte, except for one change. Each file starts with `#+vet !unused !shadowing`, so the package builds under odx's vet flags.

## How odx runs it

`odx check` prints each file in its own `odx __format` child process. A print that crashes or hangs ends that child and never `odx check`. A crash becomes a `format` finding on that file, and the rest of the result still prints. A hang ends at the timeout with the error `format-timeout`, and `odx check` exits 2. Each child prints on one thread, which the printer needs, because every `print` call clears and refills the package-level list `list_fits` in `document.odin`.

## Updating

Changing the OLS commit or the build compiler changes `format` results, so it ships under a higher rule set.

1. Copy the three files and `LICENSE` from the new OLS commit.
2. Add the `#+vet` line to each file again.
3. Update the commit and the compiler in this file, and the `#assert` on `ODIN_VERSION_HASH` in `odx/rule_format.odin`.
4. Run `mise run test` and `mise run golden`. The golden case `format-printer-crash` holds a file that crashes this copy of the printer. When a new copy prints it, replace the file with one that still crashes the printer, or drop the case. `format-fake-crash` covers the crash path either way.

`mise run fmt` skips this directory, so the files stay as upstream wrote them.
