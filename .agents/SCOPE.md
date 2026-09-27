odx is a strict, opinionated checker for Odin projects. It runs the compiler strictly, enforces rules the compiler can't know, and reports memory bugs from real runs.

Tagline: Odin checks that it's valid Odin; odx checks that it follows your project's rules.

For: me first, learning Odin and systems programming with production habits from day one; then others in the same position. One opinion, strong defaults, no rule engine. Build, install, done: no system setup.

Principle: odx reports facts, not solutions. Findings say exactly what happened and where, never how to fix it.

Workflow: write code, `odx check`, `odx run`, and `odx test` once tests exist. CI runs check and test.

All commands

- One line per finding (file:line, rule, message), sorted, so output diffs cleanly. --json for CI and scripts.
- Exit codes: 0 clean and fully checked, 1 findings, 2 couldn't do its job. 2 wins over 1.

odx check

Runs `odin check` on every package in the repository, not only those reachable from main, with -vet -strict-style -vet-using-param -disallow-do -warnings-as-errors (odx.json can replace the list), plus odx's rules, as one verdict. Compiler findings in core, vendor or external packages are dropped. odx's rules read every file, whatever its #+build tags. Test files get the compiler check only.

Roles and their built-in rules:
- pure: explicit allocators, no mutable state, no I/O imports (core:os, core:net, core:thread, core:sys/..., core:c/libc, vendor). May import only pure packages.
- service: explicit allocators, no mutable state. May import pure and service packages.
- edge: may import anything. This is where main, I/O and platform code live.
- Every role: @(require_results) on error-returning procedures.

Rules:
- Explicit allocators: every file carries `#+vet explicit-allocators`, so calls that would fall back to context.allocator or context.temp_allocator must name one.
- Dynamic arrays and maps, wherever allocators are explicit: a local `[dynamic]T` or `map[K]V` is created with `make(..., allocator)` or gets its allocator in the next statement. Otherwise append and insertion use the context allocator with no compiler error.
- @(require_results) on procedures whose last result is a project error type. Procedure values and struct fields, which can't carry attributes, are skipped.
- No mutable state: package-level variables, @(thread_local) variables and @(static) locals. Constants (`::`) and @(rodata) are allowed.
- Import boundaries: followed through your packages' whole dependency graph, so pure can't reach edge through service. Collections resolve the way the compiler resolves them.
- Every package has a role or is listed as external, and package names are unique. The compiler scopes vet and style by package name, so duplicates would blur which code is checked.

odx.json holds only: packages per role, external packages, error types, excluded directories, and optionally the compiler flags. An excluded directory is not part of the repository: odx never discovers, checks or reads anything under it, such as test fixtures that break the rules on purpose. Without odx.json, odx exits 2 and prints a minimal example.

Ignoring rules: `// odx:ignore <rules|all> <reason>` on the line where a statement starts covers that statement; at the top of a file it covers the file. Use it to experiment or to do something advanced the rules normally forbid. A reason is required, an ignore that no longer ignores anything is a finding, and the summary counts ignores so experiments don't hide.

odx run

Runs your program in a debug build and tracks every allocation made through the default allocator, including append and map insertion. It reports leaks and bad frees with size and source line, grouping repeats from the same line. It tightens the try, break, fix loop without waiting for tests.

- No code changes: odx builds against a private copy of the Odin runtime with tracking added. If that can't be set up, for example after an Odin update, it exits 2 rather than report clean.
- It reports on every exit path: normal return, os.exit, panic, failed assert and bounds-check failure. Panics and failed checks are findings with their source line. On a crash from a signal, it reports that no leak report was possible.
- The report never mixes into your program's output. Stdin and arguments pass through; your program's exit code is shown in the summary.
- Limits: it tracks only the default allocator. Allocations inside arenas, the temp allocator and custom allocators aren't tracked individually; a leaked arena shows up only if its memory came from the default allocator. Memory left for the OS to reclaim is reported.

odx test

Runs `odin test`. Failed tests are findings. `odin test` reports leaks and bad frees per test but still passes; odx test makes them findings too. Tests cover paths a single `odx run` might miss.

AddressSanitizer (run and test)

- On by default. It catches heap use-after-free, and out-of-bounds access through raw pointers or bounds-check-disabled code. Normal indexing and slicing are already bounds-checked by Odin.
- It doesn't catch arena or temp memory reused after free_all: no allocator in base or core poisons freed memory as of Odin dev-2026-09.
- odx finds a working sanitizer linker itself, remembers it until the OS, linker or Odin version changes, and uses it only for its own builds. If none works, it runs without the sanitizer and says why. Example: on macOS 26.4 and later, sanitizer runtimes older than LLVM 22.1.3 deadlock at startup.

Not odx's job

- Static leak, use-after-free or ownership analysis. Odin has no ownership model, so static guesses would be noisy and teach the rule instead of the reason. Only code that runs is checked for memory bugs.
- Tracing and effect annotations. Odin covers these: `@(deferred_out)` for self-closing spans, `#config` with `-define` to compile them out, `#caller_location` for where.

Later

- Whole-program checks from the compiler's LLVM IR, which records every resolved call and its source line. It may help find paths that reach os.exit, allocation reachable from pure roles, and explicit panics reachable from pure code; research needed, including how stable the IR is across Odin's LLVM upgrades.
- Multi-thread support: tracking in multi-threaded programs (report after threads are joined; memory freed on another thread), checking packages in parallel, and data-race detection with -sanitize:thread (research whether it has the same macOS runtime problem).
- The dynamic array and map rule extended to type aliases, struct fields and wrappers such as strings.Builder. The compiler's resolved type output (`odin doc`) may make this possible; research needed.
- SARIF output.
- Changed-files-only checks, if a project gets slow.

Never

- Baselines: new code has no legacy to tolerate.
- Custom pattern rules: grep does that.
- Fix hints, autofix or rule explanations: working out the fix is the learning.
- Severity levels or warnings: a finding is fixed or ignored with a reason.
- Style and formatting rules: the compiler flags odx runs cover them.
- Re-checking what the compiler enforces.
- Rules on base, core, vendor or external packages.
- Editor, LSP or MCP integration, or generated agent instructions.
- Plugins, a rule DSL, or build or package-manager features.
