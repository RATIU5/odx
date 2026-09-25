# Milestones

The order odx gets built in, and where each part stands. `docs/SCOPE.md` says what odx is; this file says what comes next and how to work on it.

## How to work a part

Each part goes through three steps, in order: **Guide**, **Golden**, **Code**. The steps can happen in different sessions, so the Parts table below is the record of where things stand. Every step ends with the user's review, and a step is `done` only after the user approves it.

Step states: `todo` (not started), `wip` (started, not yet presented), `review` (presented, waiting for the user), `done` (approved).

### Every session: orient first

1. Read `CLAUDE.md`, `docs/SCOPE.md` and this file, and follow their rules. SCOPE is the contract.
2. Read the current state: `git status`, `git log --oneline -10`, and the files the current step touches.
3. The current part is the first row of the table that isn't `done` in every column. Its current step is the first column that isn't `done`.
   - `review`: the user hasn't approved it yet. Ask for the review; don't start the next step.
   - `wip`: pick up where the files and git history show it stopped.
   - `todo`: start the step.
4. Read the current part's `PART_NN_<name>.md`, if it exists, and the earlier part files it builds on. `PART_01_core.md` defines the output format, the rule names and the golden case format.

### Step 1: Guide

Write `docs/milestones/PART_NN_<name>.md`. It holds the goal, done-when, decisions, facts and out-of-scope, and lists the golden cases by name. Implementation details belong in the code, not here.

- Research first: read the relevant core or compiler behavior in `$(odin root)`, and try it in a scratch dir.
- Put open questions to the user in one batch; don't choose silently.
- Set Guide to `review` and ask the user to review the file.

### Step 2: Golden

Write the cases the guide lists, in `tests/golden/pNN-<behavior>/`, in the format `PART_01_core.md` defines. Each case covers one behavior, with the smallest input that shows it. The cases are the executable spec.

- For each rule: one clear violation, one clean near-miss that must not be a finding, the edge cases SCOPE names, and the inputs that should make odx exit 2.
- Compile every Odin input with the pinned `odin` and SCOPE's flags. If the compiler already reports it, it's the compiler pass's job, not an odx rule.
- Mark every claim about Odin VERIFIED, citing `file:line` or the command output, or UNVERIFIED. Don't write a case on an UNVERIFIED claim.
- Check each expected output against SCOPE: `file:line`, rule name, a message that states facts with no fix or hint, sorting, and the exit code. Findings must be complete, and nothing may be reported twice.
- Set Golden to `review`, and give the user a table of every case: name, input summary, expected output and exit code, verification notes, and open questions.

### Step 3: Code

Implement the part until `mise run test` passes this part's golden cases and every earlier part's.

- Use the `odin` skill, and check core API signatures against `$(odin root)`.
- Golden files are the spec. Don't edit an `expected` file to match the code; if one looks wrong, ask the user.
- Set Code to `review` and ask the user to review the code. Once it's approved, move the part's facts into Facts below and add any open questions.

### Throughout

- Before relying on any fact below or in a part file, re-verify it against `$(odin root)` or with a small program. Facts go stale after Odin updates. Fix anything that turns out wrong.
- When stuck, or when SCOPE doesn't answer something, ask the user. Don't pick silently.
- Update this table in the same change as the step's work.

## Parts

| # | Part | Done when | Guide | Golden | Code |
|---|------|-----------|-------|--------|------|
| 1 | Core: CLI, odx.json, findings, output | Sorted one-line output, `--json`, exit codes 0/1/2, and a missing odx.json exits 2 with an example | done | review | todo |
| 2 | Package discovery | Every repo package is parsed and has a role or is external; duplicate names are findings | todo | todo | todo |
| 3 | Compiler pass | `odin check` runs on every package with SCOPE's flags; core, vendor and external findings are dropped and the rest deduped | todo | todo | todo |
| 4 | Ignores | `// odx:ignore` works per statement and per file, unused ignores are findings, and the summary counts ignores | todo | todo | todo |
| 5 | File and declaration rules | Missing `#+vet explicit-allocators` and mutable state are findings | todo | todo | todo |
| 6 | Import boundaries | Imports resolve like the compiler's, and role limits hold through the whole graph | todo | todo | todo |
| 7 | require_results | Error-returning procedures without the attribute are findings | todo | todo | todo |
| 8 | Dynamic array and map rule | A local dynamic array or map without an explicit allocator is a finding | todo | todo | todo |
| 9 | `odx run` | Leaks and bad frees are reported on every exit path from a patched runtime copy | todo | todo | todo |
| 10 | `odx test` | Test failures, leaks and bad frees are findings | todo | todo | todo |
| 11 | AddressSanitizer | A working sanitizer toolchain is probed and cached; run and test use it or say why they can't | todo | todo | todo |

Parts 1–4 come before the rules because every rule needs findings, packages and ignores. Parts 5–8 go from least to most heuristic.

## Facts (Odin dev-2026-09, verified 2026-09-24; re-verify before use if odin version changed)

- `odin check <dir> -no-entry-point -json-errors` gives structured errors on stderr, with absolute paths. The default `-max-error-count` is 36, so raise it. Checking is staged: a syntax or style error hides the type and vet errors behind it.
- `odin check` includes `_test.odin` files. It compiles only files whose build tags match the host target.
- `#+vet explicit-allocators` flags omitted `Allocator` parameters that default to the context allocators (make, new, delete, free, clone, aprintf and so on). It does **not** flag `append`, map insertion, or `[dynamic]T{}`/`map[K]V{}` literals. That gap is why Part 8 exists.
- `core:odin/parser` parses every file whatever its build tags, and returns ok even on a syntax error, so check `syntax_error_count`. `file.tags` holds the raw `#+` lines, and `parse_file_tags` doesn't decode `vet`. There is no type information, so Parts 6–8 are syntactic.
- `-vet` also vets packages imported through `-collection`, so odx has to filter by path. `-disable-non-constant-globals` does not forbid `g: int`.
- `core:encoding/json` covers both odx.json and `--json` output.
- `ODIN_ROOT` pointed at a copy of the root, with `base/` patched, swaps in the runtime without changing user code. `-collection:base=` is rejected. The report hooks go in `__init_context`, `runtime.exit`, the default `assertion_failure_proc` before `trap()`, `bounds_trap` and `type_assertion_trap_contextless`. `base` can't import `core:mem`, so the tracker has to live in the runtime copy. Check a free against the tracker before calling libc `free`, or libc aborts first.
- `odin test` exits 0 on leaks unless run with `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`. Leak and bad-free detail is on stderr only, as text with basenames. `ODIN_TEST_JSON_REPORT` holds only pass/fail per test.
- `-sanitize:address` on macOS: Apple clang fails to link because of an ASan version mismatch, Homebrew LLVM 20.1.8 hangs at startup, and LLVM 22.1.8 works. odx picks the toolchain by putting its clang first on PATH, and needs a startup timeout. See llvm/llvm-project#200447.

## Open questions (ask the user before the part that needs the answer)

- Build tags: odx's rules read every file, but compiler findings cover only the host target. Should SCOPE say so? (Part 3)
- Type errors inside external packages: drop them, or report them so odx never exits 0 on a broken build? (Part 3)
- Some core procs such as `fmt.aprintf` record a core line instead of the caller's. Group by the core line, capture a stack, or mark the finding as from core? (Part 9)
- A user-set `assertion_failure_proc` or a direct `libc.exit` skips the report. Report "no report possible", or accept the gap? (Part 9)
- The exact LLVM cutoff in SCOPE (22.1.3) isn't verified; only 20.1.8 hanging and 22.1.8 working were seen. Without LLVM 22 or later installed, "sanitizer off, here's why" will be the common path. (Part 11)
