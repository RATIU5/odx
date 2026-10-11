# odx

A strict, opinionated checker for Odin projects: format, naming and syntax rules on top of pinned compiler flags. Memory-checked tests and runs are planned. Terms: [GLOSSARY.md](GLOSSARY.md); principles: [docs/adr/0004-principles.md](docs/adr/0004-principles.md).

## Workflow

1. `odx check` on any repo.
2. `odx init` pins the rule set and compiler, lists failing packages as `pending`, and writes `odx.json` and `odinfmt.json`. Commit both files.
3. During development: format with odinfmt at OLS commit `dd0f85d`, which reads the `odinfmt.json` that `odx init` wrote (in this repo, `mise run fmt`), then fix what `odx check` reports. `odx test` and `odx run` are planned and don't exist yet.
4. CI installs odx and runs `odx check`. `odx test` joins it when it exists.
5. Remove `pending` entries as packages are fixed; `odx check --pending` shows what's left.
6. Upgrade: bump `version` or `odin` in `odx.json` in one commit.

## Commands

| Command | Does |
| --- | --- |
| `odx check` | Checks every package under the repo root and prints the findings. |
| `odx check --json` | Prints the same result as one JSON document on stdout. |
| `odx check --pending` | Also prints the held-back findings of pending packages. |
| `odx init` | Writes `odx.json` and `odinfmt.json` for a repo that has no `odx.json`. |
| `odx --help` | Prints the commands, the flags and the exit codes. |
| `odx --version` | Prints the release, its rule set and the compiler it supports, as `odx 0.1.0, rule set 1, odin dev-2026-09-nightly:a2fb372`. |
| `odx test`, `odx run` | Planned. Today each is a `usage` error. |

The repo root is the nearest directory above the working directory that holds `odx.json`, else the nearest that holds `.git`, else the working directory.

`odx --help` and `odx --version` need no repo, no `odx.json` and no `odin` on `PATH`. Any other spelling, such as `odx help` or `odx check --help`, is a `usage` error, and every `usage` error ends with `; run 'odx --help'`.

`odx init` writes nothing when `odx.json` exists, or when an `odinfmt.json` exists that differs from the one it writes. Both are the error `init-exists`. It leaves an `odinfmt.json` with the same bytes as it is.

## Output and exit codes

A finding is one line on stdout, `path:line:col: rule: message`. The last stdout line is the summary:

```text
odx: 0 findings, 2 ignored, 0 pending, 0 skipped (rules 1, odx 0.1.0, odin dev-2026-09-nightly:a2fb372)
```

| Exit | Means |
| --- | --- |
| 0 | No findings. |
| 1 | At least one finding. |
| 2 | An error: odx can't give a trustworthy result. Stderr has `odx: error: <code>: <message>`. |

`--json` prints `{"version":1,"findings":[...],"errors":[...],"summary":{...}}`. Each finding has `path`, `line`, `col`, `rule` and `message`. `errors` is non-empty when the exit is 2, except for a usage error, which prints no JSON.

`--pending` prints the held-back findings after the others, under the stderr line `odx: pending findings:`. In `--json` each carries `"pending": true`. The exit code doesn't change.

A package whose own compile check reports an error in its own files gets only its `odin`, `parse-unsupported`, `import-escape`, `path-case` and `ignore-invalid` findings. When that hides a finding, stderr says so with one line per package, and stdout and `--json` stay the same:

```text
odx: app: compile errors hide this package's other findings
```

Fix the compile errors and run `odx check` again to see the rest. For a pending package the line prints only with `--pending`.

`odin check` leaves out a file tagged `#+test`. Only `odin test` compiles such a file, and odx can't run `odin test`, because it links. So a compile error in a `#+test` file doesn't fail the run. odx's own rules still run on the file, and stderr names each package that holds one, with the number of files:

```text
odx: lib: the compiler doesn't check 2 files tagged #+test
```

Stdout, `--json` and the exit code stay the same. For a pending package the line prints only with `--pending`. A file named `_test.odin` without the tag is compiled and checked like any other file.

The pinned compiler sometimes dies by a signal, such as a segmentation fault, on code it checks without trouble the next time. odx runs such a check once more. When the second run ends normally, the result is the second run's, and one stderr line counts the reruns:

```text
odx: the compiler died by a signal 2 times, and odx ran it again each time
```

On a run that ends in an error, the count covers only the compiles that ran before odx stopped, so it can differ between runs.

The line doesn't change stdout, `--json` or the exit code. It also prints when the run ends in an error, after the error lines, so a run with exit 2 still shows how often the compiler crashed. When the second run also dies by a signal, the run ends with the error `compiler-output`, and the message names the package, the target and the signal's number, as in `checking 'app' for darwin_arm64 died by signal 11 twice`. odx reruns nothing else: a check that times out or exits with an unexpected code is `compiler-output` at once.

odx reads what the compiler and the formatter write through pipes, and writes no temp files. A stream that odx can't read is never taken for an empty one. It is the error `compiler-output` for the compiler and `format-failed` for the formatter, with a message that says so:

```text
odx: error: compiler-output: checking 'app' for darwin_arm64 started, but odx couldn't read its output: Input/output error
```

odx reads at most 512 MB from one stream of a compiler or formatter process. It kills a process that writes more, and the run ends with the same error:

```text
odx: error: compiler-output: checking 'app' for darwin_arm64 wrote more than 512 MB to its stderr, the most odx reads from one stream
```

An error message that quotes a compiler's stderr shows its last 40 lines. The message says how many lines the stderr has when it shows fewer.

## `odx.json`

Without `odx.json`, odx uses rule set 1 and the running compiler, treats every package as strict, and says so on stderr. An unknown key, a duplicate key or a wrong type is the error `config-invalid`.

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `version` | integer | yes | The rule set in force. |
| `odin` | string | yes | The pinned compiler, the text after `odin version `. |
| `pending` | object of directory to reason | no | Packages that aren't strict yet. A reason can't be empty. |
| `vendored` | array of directories | no | Third-party trees that odx applies no rules to. |
| `exclude_dirs` | array of directories | no | Directories odx never scans. |
| `collections` | array of `name=path` | no | Passed to the compiler. The path must be inside the repo. |
| `defines` | array of `NAME=value` | no | Passed to the compiler. |

A `pending` entry with nothing left to fix is the finding `pending-stale`, at the entry's place in `odx.json`.

## Rules

All rules belong to rule set 1. A rule that can be ignored takes an ignore with a reason. The others have no exception.

| Rule | Ignorable | Reports |
| --- | --- | --- |
| `odin` | no | An error or a warning from `odin check` with odx's strict flags. |
| `parse-unsupported` | no | A file that odx can't read or parse. [Files odx can't read](#files-odx-cant-read) lists the cases. |
| `import-escape` | no | An import, `#load` or `foreign import` path that leaves the repo. |
| `path-case` | no | A path whose case differs from the directory entry on disk. |
| `line-length` | yes | A line wider than 100 columns, with a tab counted as 4. |
| `ignore-invalid` | no | An ignore that is misspelled, names an unknown rule or a rule that can't be ignored, or covers nothing. |
| `ignore-unused` | no | An ignore that suppressed no finding. |
| `pending-stale` | no | A `pending` entry that has no findings left or names no package. |
| `block-comment` | no | A `/* */` comment. |
| `one-line-block` | no | A `{ }` block that holds a statement and opens and closes on one line. Procedure bodies are exempt. |
| `auto-cast` | no | `auto_cast`. |
| `do-stmt` | no | A `do` body. |
| `fallthrough` | yes | `fallthrough`. |
| `bounds-check-directive` | yes | `#no_bounds_check` or `#bounds_check`. |
| `vet-disabled` | no | A `#+vet` tag that turns a check off. |
| `feature-relaxed` | yes | A `#+feature` tag that turns off a compiler error. Only a whole-file ignore covers it. |
| `transmute` | yes | `transmute`. |
| `format` | no | A file that differs from the formatter's output. |
| `proc-length` | yes | A procedure body with more than 100 counted lines. |
| `nesting-depth` | yes | A block nested more than 6 levels deep. |
| `name-case` | yes | A name without its kind's case: `Ada_Case` types, `snake_case` procedures and variables, `SCREAMING_CASE` constants and package-level literal tables. |
| `package-name` | no | A `package` clause that differs from its directory's name and isn't `main`, or a directory name that isn't `snake_case`. |
| `file-name` | no | A `.odin` file name that isn't `snake_case`. |
| `import-alias` | no | An import alias equal to the name the import has without one. |
| `import-order` | no | Imports out of group order or spaced wrongly. Groups run `base:` and `core:`, then `vendor:`, then other collections, then relative paths, with one blank line between groups. |

## Packages for one platform

odx checks every package for `darwin_arm64` and `linux_amd64`. A package written for one platform says so with a build tag, such as `#+build darwin` at the top of each file, or with a file suffix such as `_darwin.odin`. odx then checks it for that target only. An `#assert(ODIN_OS == .Darwin)` alone fails on the other target, because the compiler still selects the file. A finding doesn't say which target it comes from, so a finding in a `_linux.odin` file or in a `when ODIN_OS == .Linux` branch reads like any other.

## Files odx can't read

Each case below is the finding `parse-unsupported`, which no ignore covers. The rules that need the file's syntax tree, `format` among them, don't run on that file. The rest of its package is checked as usual, except in the first case.

- A `.odin` entry that is neither a regular file nor a link to one, such as a FIFO, a socket, a device or a link to `/dev/null`. The finding is at `1:1`, and odx never opens the entry. A hidden entry such as `.notes.odin` is exempt, because the compiler never opens it.
- A link that doesn't resolve. The finding is at `1:1`.
- A file with no `package` clause, which includes a 0-byte file and a file that holds only comments. The compiler accepts a 0-byte file and reports the others, so those also get an `odin` finding.
- A file that `core:odin/parser` reports an error for.

The compiler reads every `.odin` entry of a package and of the packages it imports, and it waits forever on a FIFO. So odx doesn't run `odin check` for the package that holds such an entry. That package gets every rule except `odin`, and it is never counted as skipped. The entry still reaches the compiler when a checked package imports the package or the tree that holds it. The importer's check then waits on a FIFO until its time limit and ends the run with the error `compiler-output`.

odx opens no other path that the repo names unless it is a regular file or a directory. An `odx.json` that is anything else is the error `config-invalid`. An `odinfmt.json` that is a FIFO or a device is the error `init-exists`. A `collections` path, a `pending` entry or an import that names one is treated as a file, not a directory.

odx sets no nesting limit of its own. It parses 1,000 nested parentheses as it parses 10, and it reads at least twice as deep as the compiler does. The compiler's stack ends first, near 3,000 nested parentheses. odx runs the crashed check once more, and a compiler that crashes both times is the error `compiler-output`.

The formatter runs in its own process for each file, and that process ends when it has taken 2 GB more memory than it started with. The file then gets the `format` finding `the formatter crashed, so odx can't check this file's format`, and stderr names it. A type with 20 `proc() ->` in a row does this. The largest file measured, 2 MB of generated tables, takes 0.2 GB.

## Ignores

An ignore is a comment on its own line, directly above the code it covers:

```odin
// odx:ignore transmute reads the bit pattern of the float
bits := transmute(u32)value
```

- The form is `// odx:ignore <rule>[,<rule>...] <reason>`, with one space after `//` and one after `odx:ignore`. The reason is required.
- `all` in place of the rule list names every rule that can be ignored.
- An ignore above the `package` line covers the whole file.
- The summary counts the findings that ignores suppressed.

## Formatting

odx never rewrites code. The `format` rule compares each file with the output of OLS's odinfmt printer, which odx vendors at OLS commit `dd0f85d31c91e9d04202cc422288d15b52206474` (`odx/ols_printer/`). Format your code with an `odinfmt` built from that commit:

```sh
git clone https://github.com/DanielGavin/ols
cd ols
git checkout dd0f85d31c91e9d04202cc422288d15b52206474
./odinfmt.sh   # builds ./odinfmt with the odin on PATH, which must be the pinned compiler
```

`odx init` writes `odinfmt.json` at the repo root, so `odinfmt` uses the configuration odx checks against. A repo that already has `odx.json` copies `odinfmt.json` from the root of the odx repo, because `odx init` writes nothing there. odx itself ignores any `odinfmt.json` in the checked repo. `odinfmt -w .` also rewrites vendored trees, so pass it the directories you own, as in `odinfmt -w src`.

In the odx repo, `mise run fmt` runs the vendored printer and not the machine's `odinfmt`.

## Development

```sh
mise install
mise run build      # build/odx
mise run fmt        # format odx's sources with the vendored printer
mise run test
mise run golden     # the cases in tests/golden against build/odx
mise run selection  # rerun on every compiler bump
mise run self       # odx check on odx's own sources
```
