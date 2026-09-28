# odx

odx is a command-line checker for Odin projects, written in Odin. It runs the compiler with pinned strict flags on every package, enforces rules at package boundaries (state, imports, allocator ownership, error results), and runs tests and programs with memory-error detection.

**For:** the author and their team, shipping opinionated production Odin that has to last years. They need one set of rules, enforced the same way on every machine and in CI.

**Problem:** Odin's strict checks are opt-in, can be switched off per file, and skip `#+test` files. Nothing checks package boundaries. `odin test` hides use-after-free and passes with leaks. A strict tool also has to adopt onto existing code without a rewrite.

**Success:**

- `odx check` gives a result on an unconfigured repo in one command.
- If the code compiles and has no imports from outside the project, `odx check` goes green in one `odx init` commit, and the `pending` list only shrinks.
- A CI result changes only when code, `odx.json` or the odx major release changes.
- A new package is strict with no config edit.

**Principle:** strict at boundaries, free inside. Every deviation is stated with a reason where the team can see it. odx stops only when it can't produce a trustworthy result; everything else just works.

**Workflow:**

1. `odx check` on any repo.
2. `odx init` to pin the version and compiler and list failing packages as `pending`.
3. Commit `odx.json`.
4. `odx test` and `odx run` during development.
5. CI installs the pinned odx release and runs `odx check && odx test`.
6. Shrink `pending` over time.
7. Upgrade: preview with `odx check --next`, then bump `version` or `odin` in one commit.

## Everywhere

- **Findings:** one line each, `path:line:col: rule: message`, sorted by path, line, col, rule, message. Exact duplicates print once. Paths are repo-relative with `/`. Columns count code points, as the compiler does.
- **Messages** state the problem and where it is. No fix hints.
- **Summary** is the last stdout line: `odx: N findings, N ignored, N pending, N skipped (version V, odin X)`. What was skipped, and why, goes to stderr.
- **`--json`:** `{"version":1,"findings":[{"path","line","col","rule","message"}],"errors":[{"code","message"}],"summary":{…}}`. `errors` is non-empty exactly when the exit code is 2. The JSON schema version is separate from the config `version`.
- **Exit codes:** 0 clean; 1 findings; 2 no trustworthy result. 2 wins over 1.
- **Exit 2 reasons** go to stderr as `odx: error: <code>: <message>`:

| Code | When |
| --- | --- |
| `usage` | an unknown command, a bad flag, or an `odx run` dir that isn't a package |
| `compiler-mismatch` | the compiler's version differs from the `odin` pin |
| `compiler-unsupported` | the compiler is outside this odx release's supported range |
| `config-invalid` | `odx.json` is invalid |
| `odin-missing` | the `odin` binary can't be found |
| `compiler-output` | the compiler's output can't be read |
| `init-exists` | `odx init` finds an existing `odx.json` |

- **Rule IDs** are permanent and never reused. Message text is not part of the contract.
- **Compiler findings** use rule ID `odin` and can't be ignored.
    - Findings located in another project package are dropped; that package's own check reports them.
    - Findings in `external` dirs and the Odin root are kept.
- **Compiler output** is read from `-json-errors`, with `-max-error-count` set high enough to get every finding.
- **Repo root:** the nearest ancestor with `odx.json`, else the nearest with `.git`, else the working directory.
- **Discovery:** every directory with at least one `.odin` file is a package, except `exclude_dirs`, hidden dirs and `external` trees. Directory symlinks aren't followed. File symlinks are checked and reported at the link path.
- **Files odx's rules read:** every `.odin` file in a package except `#+build ignore` files. This includes `#+test` files and files for other platforms.
- **Skipped, not failed** (counted in the summary):
    - a package with no files for the host is not compiled. odx's rules still run on it;
    - a file outside a strict stateless package that odx's parser can't read. odx's rules skip it.
- **Without `odx.json`,** odx runs with defaults: every package `app`, the latest `version`, the running compiler. It prints one stderr note.
- **Versioning:** every change to results applies only under a higher `version`: a new rule, broader or narrower detection, a fix for a wrong finding, a new compiler flag.
- **Compiler support:** each odx release states its supported odin range. Support for an odin version is dropped only in a new major odx release.
- **Public procedure:** a package-level procedure that isn't `@(private)` and isn't in a `#+private` file. Odin is public by default, so internals opt out with `@(private)`.

## Configuration and init

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `version` | int | yes | Rule set in force |
| `odin` | string | yes | Pinned compiler: the text after `odin version `, e.g. `dev-2026-09-nightly:a2fb372` |
| `stateless` | [dir] | no | Packages with the stateless role |
| `external` | [dir] | no | Vendored trees; no rules |
| `pending` | {dir: reason} | no | Packages not yet strict |
| `exclude_dirs` | [dir] | no | Directories never scanned |
| `collections` | ["name=path"] | no | Passed to the compiler |
| `defines` | ["NAME=value"] | no | Passed to the compiler |

- When a package isn't listed in `stateless` or `external`, it is `app`.
- When a package isn't listed in `pending` or `external`, it is strict.
- A `pending` dir may also be listed in `stateless`. It keeps that role.
- When a `stateless` entry isn't a package (doesn't exist, holds no `.odin` files, or is excluded or hidden), report `config-missing-dir` at that entry's position in `odx.json` (exit 1).
- When an `external` or `exclude_dirs` entry doesn't exist, it is ignored.
- If `odx.json` isn't strict JSON, has an unknown key or a wrong type, lists a dir under both `external` and another key, has an empty `pending` reason, or names a `version` newer than odx supports, exit 2 with `config-invalid`.
- When `odx init` runs without `odx.json`, it writes:
    - the current `version` and the running compiler's version;
    - `pending` for each package with findings, with reason `odx init YYYY-MM-DD`;
    - `external` for `vendor/`, `third_party/` and `external/` trees at any depth, taking the outermost match.
- `odx init` prints to stdout, without writing them:
    - packages that meet the stateless rules, as suggestions;
    - packages that don't compile;
    - import findings it can't make pending.
- `odx init` prints `init: S strict, P pending, E external` and exits 0.

## Pending

- A `pending` package must compile and gets `import-boundary` and `import-outside-project`. It gets no strict compiler flags and no other odx rules.
- Its tests run under `odx test` without `leak` findings. All other runtime findings apply.
- The trade-off: `pending` is coarse. New violations inside a pending package stay hidden, apart from import rules. In exchange, it carries a reason, only shrinks, and needs no violation store.
- Report `pending-clean` at the entry's position in `odx.json` when a `pending` entry:
    - would have zero findings under strict settings; or
    - isn't a package (doesn't exist, holds no `.odin` files, or is excluded or hidden).

## check

- When run, odx runs `odin check` on each non-external package with files for the host, one package at a time.
    - Strict packages get `-vet -strict-style -warnings-as-errors`, scoped to that package with `-vet-packages:<name>` and `-strict-style-packages:<name>`.
    - `pending` packages get no strict flags.
    - Flags the compiler can't scope to one package, such as `-vet-using-param` and `-disallow-do`, are odx rules instead, so they never report in `external` code or the Odin root.
- `odin check` doesn't compile `#+test` files, so a green `check` alone doesn't mean they compile; `odx test` covers them.
- If a package has compiler findings, odx's own rules don't run on that package.
- odx's rules run on each package with a clean compile, and on packages not compiled for the host:

| Rule | Applies to | Finding when |
| --- | --- | --- |
| `explicit-allocators-tag` | strict stateless packages | a file lacks `#+vet explicit-allocators` |
| `vet-negation` | strict packages | a file has `#+vet !…` |
| `using-param` | strict packages | a procedure parameter is declared with `using` |
| `do-stmt` | strict packages | a statement uses `do` |
| `allocator-param` | strict packages | a public procedure calls `make`, `new` or `new_clone`, returns a slice, string, `[dynamic]`, `map`, pointer, or a same-package alias or `distinct` of one of those, and has no allocator parameter |
| `require-results` | strict packages | a public procedure lacks `@(require_results)` and its last result is a type named `Error` or ending in `_Error`, a `bool` named `ok`, or a `bool` in a procedure with two or more results; `#optional_ok` and `#optional_allocator_error` procedures are exempt |
| `stateless-state` | strict stateless packages | a package-level variable, `@(static)` or `@(thread_local)` variable, foreign-block variable, or `@(init)`/`@(fini)` procedure; `@(rodata)` and `@(static, rodata)` are allowed |
| `parse-unsupported` | strict stateless packages | the compiler accepts a file that odx's parser can't read |
| `import-boundary` | stateless packages, including pending | a direct or indirect import of a non-stateless project package |
| `import-outside-project` | all non-external packages, including pending | an import resolves outside the Odin root's base, core or vendor and outside the repo |

- An **allocator parameter** is one typed `Allocator` (through any import alias), or one with a default of `context.allocator` or `context.temp_allocator`.
- When `--next` is given, odx applies the next `version`'s rules, writes nothing, and exits by the results.

## test

- When run, odx runs `odin test` for each package that has tests.
    - Strict packages get the same scoped strict flags as `check`, so `#+test` files are checked too. Compiler findings are reported under `odin`.
    - Tests allocate from the real heap, not the rollback-stack test allocator.
    - Tests run in parallel as `odin test` does, and may start their own threads.
    - AddressSanitizer is on when a working LLVM clang is found.
    - It runs against the same patched runtime as `run`, with its thread-safe tracker.
- If no working clang is found, tests run without AddressSanitizer. stderr says why, and the summary notes `asan: off`.
- Leaks are counted at process exit and reported at the allocation site.
- Runtime findings:

| Rule | Finding when |
| --- | --- |
| `test-failed` | a test fails, including by panic or failed assert |
| `leak` | memory is still allocated at exit (size, allocation site) |
| `bad-free` | a free of memory not allocated, already freed, or allocated by a different allocator |
| `asan` | any AddressSanitizer report |
| `crash` | a fatal signal such as SIGSEGV or SIGBUS |

## run

- `odx run [dir] [-- args]` builds the package in `dir` (default: the current directory) in debug mode, against a private patched runtime matching the pinned `odin`, and runs it with `args`.
- The patched runtime's tracker is thread-safe, so programs may start threads.
- odx reports `leak` and `bad-free`, with size and source line, on every exit path:
    - normal return and `os.exit`;
    - panic, failed assert and bounds failure;
    - SIGINT and SIGTERM.
- Memory still held by running threads at exit is reported as `leak`.
- Other runtime findings:
    - `panic`: a panic, failed assert or bounds failure.
    - `crash`: a fatal signal such as SIGSEGV or SIGBUS.
    - `asan`: any AddressSanitizer report.
- Only the default heap allocator is tracked. Arenas and `temp_allocator` are not.
- AddressSanitizer follows the same rule as `test`.
- The exit code follows the odx contract (0, 1, 2). The program's own exit status goes to stderr.
- No user code changes are needed.

## Ignores

- **Grammar:** `// odx:ignore <rule>[,<rule>…] <reason>`.
    - The first token after `odx:ignore` is a comma-separated list of rule IDs, or `all`, which means every ignorable rule.
    - The rest of the line is the reason, and it can't be empty.
- **Placement:** on its own line, an ignore applies to the next statement. Consecutive ignore lines stack. Above `package`, it applies to the whole file. At the end of a code line, it is `ignore-invalid`.
- **Detection:** odx finds ignores with the tokenizer, so text inside strings is never an ignore. In files odx's parser can't read, it scans lines instead, and only whole-file ignores apply.
- **`ignore-invalid`:** an unknown rule ID, a missing reason, an end-of-line placement, or a rule that can't be ignored.
- **`ignore-unused`:** an ignore that matched no finding, counting only rules that ran on that file. Runtime rules are exempt.
- **Can't be ignored:** `odin`, `config-missing-dir`, `pending-clean`, `ignore-invalid`, `ignore-unused`, `test-failed`, `bad-free`, `asan`, `crash`.
- **Runtime ignores:** `leak` goes on the allocating statement; `panic` goes on the statement that panics or asserts. `check` validates their syntax only.
- **Summary:** counts the ignores that were applied.

## Roles and import boundaries

| Role | Default | Rules when strict | May import |
| --- | --- | --- | --- |
| `app` | yes | all strict-package rules | anything in the repo, plus base, core, vendor |
| `stateless` | no | strict-package rules, plus `explicit-allocators-tag`, `stateless-state`, `parse-unsupported`, `import-boundary` | stateless project packages, plus base, core, vendor |
| `external` | no | none | anything |

- When a stateless package imports a non-stateless project package, directly or indirectly, report `import-boundary` at the import.
- When a non-external import resolves, by real path, outside the Odin root's base, core or vendor and outside the repo, report `import-outside-project`. This includes `core:../..` escapes and imports through symlinks that leave the repo.

## Not its job

- **Formatting and style:** the compiler's `-strict-style` and odinfmt cover them.
- **Re-checking what the compiler enforces:** odx pins the flags instead.
- **Editor integration:** OLS runs the compiler's checks.
- **Deciding what goes in `pending`:** code review decides.
- **Leak tracking for arenas and `temp_allocator`:** they free in bulk.

## Later

- **`targets`:** checking packages for other platforms; whether `odin check -target` works without a linker or SDK.
- **`temp-use-after-reset`:** poisoning `temp_allocator` memory on reset needs new runtime patching.
- **Type resolution from `odin doc`** for `require-results` and `allocator-param`: the format changes every compiler release, and it omits private and nested procedures.
- **SARIF output:** which viewers matter.
- **Changed-files mode:** whether it can stay correct across the import graph.
- **Allocator coverage for `append`, maps and `tprint` inside `#+vet`:** depends on the Odin maintainers.

## Never

- **Baselines or violation stores:** they drift and hide swapped violations.
- **Severity levels:** a finding is fixed or ignored with a reason.
- **Plugins, custom rules, a rule DSL:** one opinion.
- **Fix hints and autofix:** the fix is the developer's call.
- **Rules on external code:** it isn't the team's code.
- **Ignoring compiler findings.**

## Risks

- **`-warnings-as-errors`:** a warning in base, core or vendor becomes an error that can't be ignored. None appear in `fmt`, `os`, `encoding/json`, `odin/parser`, `thread`, `net` or `vendor:stb/image` at `dev-2026-09`; re-probe on each compiler bump.
- **Thread-safe tracker overhead:** measure lock cost on every allocation under `odx test` with parallel tests.
- **`-json-errors` has had truncation and duplication bugs:** fuzz odx's reader with large error counts.
- **The patched runtime must track each compiler version:** keep the supported range narrow within a major release; majors follow Odin's release pace.
- **Detecting fatal signals in the patched runtime:** confirm on each supported OS.
- **Checking each package separately is slower on large repos:** measure; run packages in parallel if needed.
- **`allocator-param` false positives** on procedures that return views into existing memory: measure on real code.
- **Parser lag:** how often `parse-unsupported` fires on real stateless code.

## Open questions

- For `crash` and `panic`, which stack frame is the reported `path:line`: the innermost frame in repo code?
