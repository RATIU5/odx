# Milestones

The order odx gets built in, and where each part stands. `.agents/SCOPE.md` says what odx is; this file says what comes next and how to work on it.

## How to work a part

Each part goes through three steps: **Guide**, **Golden**, **Code**. Each ends with the user's review; a step is `done` only after approval. The Parts table is the record of where things stand.

States: `todo`, `wip` (started), `review` (presented, waiting for the user), `done` (approved).

### Every session

1. Read `CLAUDE.md`, `.agents/SCOPE.md` and this file.
2. Read `git status`, `git log --oneline -10`, and the files the current step touches.
3. The current part is the first row not `done` in every column; its current step is the first column not `done`.
   - `review`: ask for the review; don't start the next step.
   - `wip`: continue from where the files and git history stop.
   - `todo`: start it.
4. Read the current part's `PART_NN_<name>.md` and the earlier part files it builds on. `PART_01_core.md` defines the output format and the golden case format.

Do one step, then stop for review.

### Guide

Write `.agents/milestones/PART_NN_<name>.md`: goal, done-when, decisions, facts, open questions, out-of-scope, and the golden cases by name. How the code works belongs in the code.

- Research in `$(odin root)` and in a scratch directory.
- Check every decision against SCOPE. What SCOPE doesn't answer is an open question.
- Ask open questions in one batch.
- Set Guide to `review`.

### Golden

Write the listed cases in `tests/golden-NN/<behavior>/`, in Part 1's format. One behavior per case, smallest input that shows it.

- Per rule: a violation, a near-miss that isn't a finding, SCOPE's edge cases, and the inputs that exit 2.
- Compile every Odin input with the pinned `odin`. What the compiler with SCOPE's flags reports is the compiler pass's job.
- Mark each claim about Odin VERIFIED (`file:line` or command output) or UNVERIFIED. No case rests on an UNVERIFIED claim.
- Check each expected output against SCOPE: `path:line:col`, rule ID, a factual message with no hint, order, deduplication, exit code. Complete, and nothing twice.
- Set Golden to `review` and give the user a table: case, input, expected output and exit code, verification, open questions.

### Code

Implement until `mise run test` passes this part's cases and every earlier part's.

- Use the `odin` skill; check signatures against `$(odin root)`.
- Never edit an `expected` file to match the code. If one looks wrong, ask.
- Keep to this part.
- Set Code to `review`. Once approved, move lasting facts into Facts below.

### Throughout

- Re-verify a fact before relying on it if the pinned Odin changed.
- When SCOPE is silent or wrong, ask the user. SCOPE changes only through the `scope` skill.
- Update the table in the same change as the work.

### Every Odin bump

1. Parse every file in `$(odin root)/base`, `core` and `vendor` with `core:odin/parser`; list the files it can't read.
2. Re-verify every fact below.
3. Re-probe which strict flags `-vet-packages` and `-strict-style-packages` scope, and whether `-warnings-as-errors` fires in base, core or vendor.
4. Re-check the patched runtime's hook points and the `#+vet` names.

## Parts

| # | Part | Done when | Guide | Golden | Code |
|---|------|-----------|-------|--------|------|
| 1 | Core: CLI, odx.json, output | Every command parses its arguments (else `usage`), finds the repo root, reads `odx.json` strictly or runs on defaults, and prints findings, summary, `--json` and exit-2 codes as SCOPE says | todo | todo | todo |
| 2 | Discovery and roles | Every package is found, with excluded, hidden and external trees skipped and symlinks handled; each gets its role and strictness; its files are parsed; bad `stateless` entries are `config-missing-dir` | todo | todo | todo |
| 3 | Compiler pass | The `odin` pin is enforced, each package is checked alone with scoped strict flags, findings in other project packages are dropped, and odx's rules run only after a clean compile or on packages with no host files | todo | todo | todo |
| 4 | Ignores | `// odx:ignore` is found with the tokenizer and applies to the next statement or the whole file; `ignore-invalid`, `ignore-unused` and the ignored count follow SCOPE | todo | todo | todo |
| 5 | File and statement rules | `explicit-allocators-tag`, `vet-negation`, `using-param`, `do-stmt`, `stateless-state` and `parse-unsupported` report where SCOPE says | todo | todo | todo |
| 6 | Imports | Imports resolve by real path; `import-boundary` follows the whole graph and `import-outside-project` covers every non-external package | todo | todo | todo |
| 7 | Procedure rules | `require-results` and `allocator-param` report public procedures as SCOPE defines them | todo | todo | todo |
| 8 | Pending, init, `--next` | `pending-clean` reports clean or stale entries, `odx init` writes and prints what SCOPE says, and `--next` checks under the next `version` | todo | todo | todo |
| 9 | Patched runtime and `odx run` | `odx run` reports `leak`, `bad-free`, `panic` and `crash` on every exit path SCOPE lists, threads included | todo | todo | todo |
| 10 | `odx test` | Tests run per package with scoped strict flags, on the heap and the patched runtime, with SCOPE's runtime findings and no `leak` for pending packages | todo | todo | todo |
| 11 | AddressSanitizer | `test` and `run` report `asan` with a working LLVM clang, or run without it and report `asan: off` | todo | todo | todo |

Every rule needs output, packages, the compiler pass and ignores, so Parts 1–4 come first. Parts 5–7 go from least to most heuristic. Part 8 needs every check rule. `test` reuses `run`'s patched runtime, and ASan builds on both.

## Facts

Pin `dev-2026-09` = `odin version dev-2026-09-nightly:a2fb372`. Verified 2026-09-27 unless marked otherwise; re-verify after a bump.

### Compiler and flags

- `odin check <dir> -no-entry-point -json-errors` writes errors to stderr with absolute paths. `-max-error-count` defaults to 36. Checking is staged: a syntax or style error hides later type and vet errors.
- `-json-errors` labels syntax and `-strict-style` errors `"type":"warning"`; don't rely on `type`. Fixed upstream in PR #7550, after this pin.
- odin-lang/Odin#7072: `odin check -vet` can segfault (parser data race). A compiler crash is `compiler-output`.
- `-vet` = unused-variables, unused-imports, shadowing, using-stmt, deprecated, cast (`build_settings.cpp:323`).
- `-vet-packages` and `-strict-style-packages` match package names and scope `-vet` and `-strict-style` (probe).
- `-vet-using-param` and `-disallow-do` apply to every file the compiler reads, core included (probe). Core and vendor use `do` only in comments.
- `-warnings-as-errors` reports nothing from `fmt`, `os`, `encoding/json`, `odin/parser`, `thread`, `net` or `vendor:stb/image` (probe). Not proven for all of core.
- Two same-named packages in one import graph are a compile error, so name scoping can't match the wrong package (probe).
- A file's `#+vet` tag adds to the command-line flags, escapes `-vet-packages`, and supports `!` negation (`parser.cpp:7154-7167`).
- `#+vet explicit-allocators` fires only when a call omits a parameter whose default is `context.allocator` or `context.temp_allocator` (`check_expr.cpp:6916`). It misses `append`, map insertion, `fmt.tprint*` and dynamic literals.
- `odin check` skips `#+test` files entirely, type errors included; `odin test -vet` checks them. `_test.odin` files are compiled by `odin check` (probe).
- `odin check` compiles only files whose build tags match the target.
- Columns count code points; `core:odin/tokenizer` counts bytes.
- The compiler reads symlinked `.odin` files and reports positions at the target path.
- Import paths are joined, not contained: `core:../../x` escapes the collection (`parser.cpp:6848-6853`). `-collection:shared=` is accepted; `core` can't be redefined.

### Parser and declarations

- `core:odin/parser` parses every file whatever its build tags and returns ok on a syntax error; check `syntax_error_count`. `file.tags` holds raw `#+` lines; `parse_file_tags` doesn't decode `vet`. No type information. (2026-09-24)
- `core:odin/parser` can't read triple-quoted `"""` strings: 3 of 1618 files in base, core and vendor, plus the `base/intrinsics` and `base/builtin` pseudo-files.
- `Value_Decl.pos` is the name's position; attributes have their own, earlier position.
- `@(require_results)` on a proc group is ignored; on a foreign block it applies to every member.
- `#optional_allocator_error` exists (`core/strings/conversion.odin:24`).
- `@(static, rodata)` locals are legal. Foreign-block variables are writable. Map literals can't be constants or `@(rodata)`.
- `odin doc -doc-format` omits `@(private)`, `@(private="file")` and nested procedures (probe).

### odx.json

- `core:encoding/json` skips a BOM, accepts trailing commas and trailing text, and stops at NUL, so odx.json needs a strict reader on `json.Tokenizer`.

### Runtime, tests and sanitizer

- `ODIN_ROOT` pointed at a copy with a patched `base/` swaps the runtime without user code changes; `-collection:base=` is rejected. Hooks: `__init_context`, `runtime.exit`, the default `assertion_failure_proc` before `trap()`, `bounds_trap`, `type_assertion_trap_contextless`. `base` can't import `core:mem`, so the tracker lives in the runtime copy. Check a free against the tracker before libc `free`. (2026-09-24)
- `odin test` always runs tests on a `thread.Pool`, even with `ODIN_TEST_THREADS=1` (`core/testing/runner.odin:374-392`).
- `odin test` gives each test a tracking allocator over a rollback stack (`core/testing/runner.odin:36-40`), so ASan misses use-after-free there; on `runtime.heap_allocator()` it's caught (probe).
- `odin test` exits 0 on leaks unless `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`. Leak detail is stderr text with basenames only. (2026-09-24)
- `-sanitize:address` on macOS: Homebrew LLVM 20.1.8 hangs at startup, 22.1.8 works (llvm/llvm-project#200447). Apple clang fails to link ASan on macOS 27.2. `ODIN_CLANG_PATH` selects the linking clang (`src/linker.cpp:447-448`).

## Open questions

Ask before the part that needs the answer.

- Part 1: what fields does the `--json` `summary` object hold?
- Part 3: is the first release's supported `odin` range only `dev-2026-09`?
- Part 8: what does `pending-clean` mean for a pending package with no host files?
- Part 8: what does `--next` do when no higher `version` exists?
- Part 9: which frame is the `path:line` for `crash`, `panic`, and a `leak` allocated inside core: the innermost repo frame? (SCOPE open question)
- Part 9: a user-set `assertion_failure_proc` or a direct `libc.exit` skips the report. Report nothing, or `crash`?
- Part 10: how do tests get the heap and the tracker without code changes: patch `core/testing` in the runtime copy?
- Part 11: where does `asan: off` go in the summary line?
- Part 11: how does odx tell an ASan startup hang from a program waiting on input: a version cutoff or a timed test build?
