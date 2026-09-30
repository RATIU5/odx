# odx: decisions

Scopes: `.agents/SCOPE.md`, `.agents/scopes/check.md`, `.agents/scopes/memory.md`. This log covers all three. Only decisions still in force are kept; the full history is in git.

## 2026-09-27

- Q: Flags the compiler can't limit to one package (`-vet-using-param`, `-disallow-do`)? → A: odx rules. Why: probes showed they report inside vendored code and the Odin root. (check)

## 2026-09-29, first pass

- Q: Enforce Ginger Bill's opinions as a goal? → A: No; the user adopts the ones they agree with. (For)
- Q: How do `test` and `run` detect memory problems? → A: One mechanism: a generated wrapper with a tracking allocator for `run`, the stock runner with `ODIN_TEST_FAIL_ON_BAD_MEMORY` for `test`. No runtime patch, ASan or clang; limits documented. Why: simple, automatic, Odin compiler only. (memory)
- Q: Extra compiler flags? → A: `-vet-cast` only. `-vet-tabs` declined; `-vet-semicolon` and `-vet-style` are covered by `-strict-style`; `-vet-unused-procedures` flags every public procedure (probe). (check)
- Q: Naming? → A: `name-case` covers locals, `foreign` blocks and parametric names (`Ada_Case`); `X :: Y` follows `Y`, or `Ada_Case` for built-in types; all-caps acronyms allowed in `Ada_Case`; findings at the name. (check)
- Q: Structural naming? → A: `package-name` (at each `package` clause; repo root only needs `snake_case`), `file-name`, `import-alias`. (check)
- Q: Where does `crash` point? → A: The file declaring `main`, at 1:1. A `@(private)` `main` in `odx run` is `usage`. (memory, SCOPE)

## 2026-09-29, restructure

- Q: Layout? → A: `SCOPE.md` for product and shared core, `scopes/check.md`, `scopes/memory.md`; the checker is built first. (all)
- Q: Names for the halves? → A: Checker and memory checker. (GLOSSARY)
- Q: Formatting? → A: Stricter than odinfmt, using it rather than replacing it: vendor OLS's printer with a fixed config, report `format`; the team formats with odinfmt and fixes the rest by hand. Why: reproducible CI; odx never changes user code, so no `odx fmt`. (check, Never)
- Q: Formatter config? → A: 4 spaces, width 100, 1TBS, LF, sorted imports, `newline_limit` 1, other settings pinned explicitly. (check)
- Q: Formatter updates? → A: Only in a major release; each release states its OLS commit. (SCOPE)
- Q: Layout rules beyond odinfmt? → A: `block-comment`, `one-line-block`, `line-length`. `blank-lines` dropped: `newline_limit` 1 covers it. (check)
- Q: v1 checker content? → A: Compiler pass, formatting, naming and syntax rules, ignores, `pending`, `vendored`, `import-escape`. Pure packages and ownership rules (`allocator-param`, `require-results`) move to Later. (check)
- Q: Syntax rules? → A: `auto-cast`, `do-stmt`, `naked-return`, `bounds-check-directive`, `transmute`, `cast-style` (`cast(T)x` wins), `import-order`, `fallthrough`, `proc-length` (≤ 100), `nesting-depth` (≤ 6), `using-param`. `using` struct fields stay allowed. (check)
- Q: Where rules apply? → A: Strict packages, every file odx reads; pending gets only `import-escape`; vendored gets nothing. (check)
- Q: `format` ignorable? → A: No. (SCOPE)
- Q: Names? → A: `external` → `vendored`, `vet-negation` → `vet-disabled`, `import-outside-project` → `import-escape`, `pending-clean` → `pending-stale`, stateless → pure. (all)
- Q: Principles? → A: The eight in SCOPE; "adopt without a rewrite" became "fix, don't accept". (SCOPE)
- Q: Adoption? → A: Keep `init` and `pending`; removing an entry forces strict; `odx check --pending` shows pending findings without changing the exit code. (SCOPE)
- Q: Memory checker scope? → A: Goals now, with the existing design kept as a draft. "Debugger" means precise sites and backtraces, non-interactive. A panic in core is reported at the innermost repo frame. (memory)
- Q: Non-ASCII names? → A: Always a `name-case` finding. (check)
- Q: Does odx check itself? → A: It will; not enforced yet. (Later)

## 2026-09-29, edge-case check

- Q: How are pending packages compiled? → A: odx is a layer on valid Odin: every package must compile, with findings under `odin`. The strict results for a pending package are held back, used for `pending-stale` and shown with `--pending`. (SCOPE)
- Q: `import-escape`? → A: Can't be ignored; runs even when a package has compiler findings. (SCOPE, check)
- Q: `--pending` output? → A: Same format, after other findings under a stderr header; `"pending": true` in JSON; summary counts pending packages and skipped packages and files. (SCOPE)
- Q: Unlisted name kinds? → A: Labels, import aliases, `foreign import` names and `bit_field` fields are `snake_case`; `#config` constants and parametric values are `SCREAMING_CASE`. (check)
- Q: Directory name not `snake_case`? → A: Always a `package-name` finding. (check)
- Q: Ignore listing a rule that can't be ignored? → A: The whole ignore is invalid and suppresses nothing. (SCOPE)
