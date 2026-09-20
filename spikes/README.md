# M0 feasibility spikes (run 2026-09-20, odin dev-2026-09:a2fb372b7)

Build: `mise run spikes`. Each spike is a throwaway program; results feed M1/M2 design.

## docshort: parse `odin doc` into (kind, name, signature, doc)

`./build/spike_docshort spikes/sample/lib`

- **`-short` drops doc comments.** Parse the full `odin doc <pkg>` form instead.
- Layout is stable and tab-indented: `\tsection`, `\t\tNAME :: SIG [/* n!m */]`, `\t\t\tdoc`.
  Variables use `name: type`. Trailing `/* 34!174 */` is a file!offset marker; strip it.
- ~35 lines of `core:strings`. 6/6 entries from the sample parsed with docs attached.
- Decision: `odx check api` (M5) can use this text form, but `-doc-format` (below) gives the
  same data typed. Prefer doc-format; keep text parse only as a fallback on `Reader_Error`.

## docfmt: `.odin-doc` for a multi-package project, joined to the AST

`./build/spike_docfmt spikes/sample/app`

- Format version 0.3.2. `-all-packages` on a 2-package sample: 444 KB, 1763 entities, 4 pkgs
  (2 project + base:runtime + builtin). Filter by `Pkg_Flags{.Runtime,.Builtin}` and path.
- **Join to AST by (file basename, line, column) hit 8/8 entities**; every one maps to a
  `Value_Decl` whose `is_mutable` agrees with `Entity_Kind.Variable`.
- `@(private)` absent (confirmed). `require_results` shows as attr `require_results=""`.
- Type errors => exit 1 and **no file written**; spike removes the old file first and checks
  `os.exists` after. Same rule for odx (19.2).

## astwalk: walk + parse + visit every node, arena per package

`./build/spike_astwalk <root>` (debug build) / `spike_astwalk_fast` (`-o:speed`)

| tree           | dirs | files | nodes     | debug   | -o:speed |
| -------------- | ---- | ----- | --------- | ------- | -------- |
| spikes/sample  | 2    | 2     | 98        | 1 ms    |          |
| `$(odin root)/core`   | 264  | 1281  | 4.3 M     | 2.07 s  | 0.48 s   |
| `$(odin root)/vendor` | 65   | 287   | 0.6 M     |         | 0.11 s   |

- Directory walk itself is negligible (14 ms for core); parse dominates. ~2.7 µs/node at speed.
  A real project (tens of packages) is well under 100 ms: `--fast` hooks are viable without caching.
- Arena-per-package with `arena_free_all` works; no leak accounting needed.
- `Parser.err` has no user data; a no-op handler compiles, so the thread-local collector in 17.20 stands.
- The 1075 "syntax errors" in core are all `core/rexcode/isa/*/tablegen/cpp-compiler/*.odin`
  (C++ templates with an .odin extension), not parser bugs. odx never parses core anyway.

## `odin check` flag list (verified with `odin help check`)

Accepted: `-vet -vet-unused -vet-unused-variables -vet-unused-imports -vet-unused-procedures
-vet-shadowing -vet-using-stmt -vet-using-param -vet-cast -vet-semicolon -vet-style -vet-tabs
-vet-packages: -strict-style -strict-style-packages: -warnings-as-errors -json-errors
-terse-errors -error-pos-style: -collection: -custom-attribute: -ignore-unknown-attributes
-define: -disallow-do -disable-non-constant-globals -foreign-error-procedures -no-entry-point
-target: -thread-count: -max-error-count: -show-unused -show-import-graph -export-dependencies:`.
Not accepted by `check` (build/test only): `-no-bounds-check -disable-assert -no-type-assert
-sanitize:`. There is no `-vet-explicit-allocators` (file tag only, 17.2).

## mise note

Pinned `odin = "dev-2026-09"` resolves to the same commit as Homebrew's odin (`a2fb372`).
