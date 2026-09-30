# odx

odx is one command-line tool, written in Odin, that solves two problems for Odin projects. The **checker** (`odx check`, `odx init`) enforces a strict, opinionated standard for format, naming and syntax without running code. The **memory checker** (`odx test`, `odx run`) runs code and reports leaks, bad frees and crashes. Terms: `.agents/GLOSSARY.md`.

| File | Covers |
| --- | --- |
| this file | goals, principles, and the core both halves share |
| `.agents/scopes/check.md` | the checker: compiler pass, formatting, naming, syntax rules |
| `.agents/scopes/memory.md` | the memory checker: goals and draft design |

The checker is built first.

**For:** the author and their team, shipping production Odin that has to last years. They need one standard, enforced the same way on every machine and in CI.

**Problem:** Odin's strict checks are opt-in, can be switched off per file, and skip `#+test` files. Nothing checks format, names or syntax choices beyond that. `odin test` passes with leaks and bad frees by default.

**Success:**

- `odx check` gives a result on an unconfigured repo in one command.
- If the code compiles and has no import that escapes the project, `odx check` goes green in one `odx init` commit, and the `pending` list only shrinks.
- A CI result changes only when the code, `odx.json` or the odx major release changes.
- A new package is strict with no config edit.
- Every command needs only the Odin compiler: no other toolchain, and no changes to user code.

**Principles**, in order:

1. **One opinion.** No rule settings, no severities, no plugins.
2. **One way to write each thing.** Where Odin allows two forms, odx picks one.
3. **Every exception is visible.** An ignore or `pending` entry carries a reason and sits in the repo.
4. **Reproducible.** A result depends only on the code, `odx.json` and the odx release.
5. **Fix, don't accept.** Code that breaks the standard never passes. `pending` schedules a fix; it never accepts the code, and it only shrinks.
6. **Findings state what and where.** No hints, no fixes, and odx never changes user code.
7. **Odin compiler only.** No other toolchain; no patches to user code, the compiler or the runtime.
8. **Stop only when untrustworthy.** Exit 2 means no result; everything else runs.

**Workflow:**

1. `odx check` on any repo.
2. `odx init` pins the release and compiler and lists failing packages as `pending`. Commit `odx.json`.
3. During development: format with odinfmt, then fix what `odx check` reports; use `odx test` and `odx run`.
4. CI installs the pinned odx release and runs `odx check && odx test`.
5. Remove `pending` entries as packages are fixed; `odx check --pending` shows what's left.
6. Upgrade: bump `version` or `odin` in one commit.

## Output

- **Findings:** one line each, `path:line:col: rule: message`, sorted by path, line, col, rule, message. Exact duplicates print once. Paths are repo-relative with `/`. Columns count code points, as the compiler does.
- **Summary**, the last stdout line: `odx: N findings, N ignored, N pending, N skipped (version V, odin X)`, where `pending` counts pending packages and `skipped` counts skipped packages and files. What was skipped, and why, goes to stderr.
- **`--json`:** `{"version":1,"findings":[{"path","line","col","rule","message"}],"errors":[{"code","message"}],"summary":{…}}`. `errors` is non-empty exactly when the exit code is 2. The JSON schema version is separate from the config `version`.
- **Position:** unless a rule says otherwise, a finding is reported at the start of the construct it names; a file-level finding with no construct is reported at 1:1.
- **Rule IDs** are permanent and never reused. Message text is not part of the contract.
- **Exit codes:** 0 clean; 1 findings; 2 no trustworthy result. 2 wins over 1. An exit-2 reason goes to stderr as `odx: error: <code>: <message>`:

| Code | When |
| --- | --- |
| `usage` | an unknown command, a bad flag, or an `odx run` dir that isn't a package with a public `main` |
| `compiler-mismatch` | the compiler's version differs from the `odin` pin |
| `compiler-unsupported` | the compiler is outside this odx release's supported range |
| `config-invalid` | `odx.json` is invalid |
| `odin-missing` | the `odin` binary can't be found |
| `compiler-output` | the compiler's output can't be read |
| `init-exists` | `odx init` finds an existing `odx.json` |

## Packages

- **Repo root:** the nearest ancestor with `odx.json`, else the nearest with `.git`, else the working directory.
- **Discovery:** every directory with at least one `.odin` file is a package, except `exclude_dirs`, hidden dirs and `vendored` trees. Directory symlinks aren't followed. File symlinks are checked and reported at the link path.
- **Files odx reads:** every `.odin` file in a package except `#+build ignore` files, including `#+test` files and files for other platforms.
- **Status:** a package is `vendored` when listed under `vendored`, `pending` when listed under `pending`, and strict otherwise.
- **Skipped, not failed** (counted in the summary): a package with no files for the host isn't compiled, though odx's own rules still run on it; a file odx's parser can't read is skipped by odx's rules.

## Configuration

`odx.json`. Without it, odx runs with every package strict, the latest `version` and the running compiler, and prints one stderr note.

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `version` | int | yes | Rule set in force |
| `odin` | string | yes | Pinned compiler: the text after `odin version `, e.g. `dev-2026-09-nightly:a2fb372` |
| `pending` | {dir: reason} | no | Packages not yet strict |
| `vendored` | [dir] | no | Third-party trees; no rules |
| `exclude_dirs` | [dir] | no | Directories never scanned |
| `collections` | ["name=path"] | no | Passed to the compiler |
| `defines` | ["NAME=value"] | no | Passed to the compiler |

- If `odx.json` isn't strict JSON, has an unknown key or a wrong type, lists a dir under both `vendored` and `pending`, has an empty `pending` reason, or names a `version` newer than odx supports, exit 2 with `config-invalid`.
- A `vendored` or `exclude_dirs` entry that doesn't exist is ignored.
- **Versioning:** every change to results applies only under a higher `version`: a new rule, broader or narrower detection, a fix for a wrong finding, a new compiler flag. The exception is a formatter update, which ships only in a major odx release.
- **Support:** each odx release states its supported Odin range and the OLS commit its formatter comes from. Support for an Odin version is dropped only in a major release.

## Pending and init

- odx is a layer on valid Odin: every non-vendored package, pending included, must compile, and its compiler findings are reported under `odin`.
- A `pending` package is also compiled and checked as strict, but those results are held back: they decide `pending-stale` and are shown only with `--pending`. Otherwise it gets only `import-escape`. Its tests run under `odx test` without `leak` findings; all other runtime findings apply.
- When `--pending` is given, the held-back findings print after all others, in the same format, under the stderr line `odx: pending findings:`; in `--json` they carry `"pending": true`. The exit code doesn't change.
- Report `pending-stale` at the entry's position in `odx.json` when a `pending` entry would have zero findings as strict, or isn't a package (doesn't exist, holds no `.odin` files, or is excluded or hidden).
- When `odx init` runs without `odx.json`, it writes:
    - the current `version` and the running compiler's version;
    - `pending` for each package with findings, with reason `odx init YYYY-MM-DD`;
    - `vendored` for `vendor/`, `third_party/` and `external/` trees at any depth, taking the outermost match.
- `odx init` prints to stdout the packages that don't compile and the `import-escape` findings it can't make pending, then `init: S strict, P pending, V vendored`, and exits 0.

## Ignores

- **Grammar:** `// odx:ignore <rule>[,<rule>…] <reason>`. The first token is a comma-separated list of rule IDs, or `all` for every ignorable rule. The reason is the rest of the line and can't be empty.
- **Placement:** on its own line, an ignore applies to the next statement or declaration, and consecutive ignore lines stack. Above `package`, it applies to the whole file.
- **Detection:** odx finds ignores with the tokenizer, so text in strings is never an ignore. In a file odx's parser can't read, it scans lines, and only whole-file ignores apply.
- **`ignore-invalid`:** an unknown rule ID, a missing reason, an ignore at the end of a code line, or a rule that can't be ignored. An invalid ignore suppresses nothing.
- **`ignore-unused`:** an ignore that matched no finding, counting only rules that ran on that file. Runtime rules are exempt.
- **Can't be ignored:** `odin`, `format`, `import-escape`, `pending-stale`, `ignore-invalid`, `ignore-unused`, and the runtime rules `memory.md` names.
- The summary counts the ignores that were applied.

## Not its job

- **Formatting code:** the team runs odinfmt; odx only reports.
- **Editor integration:** OLS runs the compiler's checks.
- **Deciding what goes in `pending`:** code review decides.

## Later

- **`--next`:** previewing the next `version`'s rules; useful once a second `version` exists.
- **Checking odx with odx:** odx will pass its own `odx check`; not yet enforced.
- **`targets`:** checking packages for other platforms, if `odin check -target` works without a linker or SDK.
- **SARIF output:** which viewers matter.
- **Changed-files mode:** whether it can stay correct across the import graph.

## Never

- **Baselines or violation stores:** they drift and hide swapped violations.
- **Severity levels or rule settings:** a finding is fixed or ignored with a reason.
- **Plugins, custom rules, a rule DSL:** one opinion.
- **Fix hints, autofix or a format command:** odx never changes user code; the fix is the developer's call.
- **Rules on vendored code:** it isn't the team's code.
- **Ignoring compiler findings.**
- **Patching the compiler or the Odin runtime.**

## Risks

- **`-json-errors` has had truncation and duplication bugs:** fuzz odx's reader with large error counts.
- **Checking each package separately is slower on large repos:** measure; run packages in parallel if needed.
