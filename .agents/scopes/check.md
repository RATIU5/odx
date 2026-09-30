# Checker

`odx check` enforces format, naming and syntax on strict packages without running code. Output, config, packages, `pending` and ignores: `.agents/SCOPE.md`.

## Compiler pass

- odx runs `odin check` on each non-vendored package with files for the host, one package at a time, reading `-json-errors` with `-max-error-count` high enough to get every finding.
- Strict packages get `-vet -vet-cast -strict-style -warnings-as-errors`, limited to that package with `-vet-packages:<name>` and `-strict-style-packages:<name>`. Pending packages get no strict flags.
- Flags the compiler can't limit to one package (`-vet-using-param`, `-disallow-do`) are odx rules instead, so they never report in vendored code or the Odin root.
- Compiler findings use rule `odin`. Findings located in another project package are dropped, because that package's own check reports them. Findings in vendored trees and the Odin root are kept.
- `odin check` skips `#+test` files, so a green check doesn't mean they compile; `odx test` compiles them.
- If a package has compiler findings, odx's own rules skip it, except `import-escape`. They run on each package that compiles cleanly, and on packages not compiled for the host.

## Rules

Every rule below applies to strict packages, in every file odx reads, except `import-escape`, which also applies to pending packages.

| Rule | Finding when |
| --- | --- |
| `format` | a file differs from the formatter's output; reported once, at the first differing line |
| `block-comment` | a `/* */` comment |
| `one-line-block` | a `{ }` block holding a statement opens and closes on one line |
| `line-length` | a line is longer than 100 code points, counting a tab as 4 |
| `name-case` | a declared name doesn't have its kind's case (see Naming), reported at the name |
| `package-name` | a `package` clause names something other than its directory, reported at the clause; the repo-root package only needs `snake_case`; a directory name that isn't `snake_case` is always a finding |
| `file-name` | a `.odin` file name, without the extension, isn't `snake_case` |
| `import-alias` | an import alias equals the imported package's name |
| `import-order` | imports aren't grouped as base, core, vendor, all other collections as one group, then relative paths, in that order, with one blank line between groups |
| `import-escape` | an import resolves, by real path, outside the repo and outside the Odin root's base, core and vendor, including `core:../..` and symlink escapes |
| `auto-cast` | `auto_cast` is used |
| `cast-style` | a conversion is written `T(x)` instead of `cast(T)x` |
| `transmute` | `transmute` is used |
| `do-stmt` | a statement uses `do` |
| `naked-return` | a bare `return` in a procedure with named results |
| `fallthrough` | `fallthrough` is used |
| `bounds-check-directive` | `#no_bounds_check` or `#bounds_check` is used |
| `using-param` | a procedure parameter is declared with `using` |
| `vet-disabled` | a file has `#+vet !…` |
| `proc-length` | a procedure body has more than 100 lines, not counting blank lines and comment-only lines; reported at the procedure's name |
| `nesting-depth` | a block is nested more than 6 deep in a procedure body; reported at that block |

- **Nesting and length:** each `if`, `for`, `switch`, `when` or bare `{ }` body adds one level, and case clauses add none beyond their switch. A procedure literal starts its own count, and its lines don't count toward the enclosing procedure.
- `using` statements are a compiler finding (`-vet` includes `-vet-using-stmt`); `using` struct fields are allowed.

## Formatting

The formatter is OLS's odinfmt printer, vendored into odx at the commit the release states, with this fixed config. Any `odinfmt.json` in the repo is ignored.

| Setting | Value |
| --- | --- |
| `spaces` / `tabs` | 4 / false |
| `character_width` | 100 |
| `brace_style` | 1TBS |
| `newline_style` | LF |
| `newline_limit` | 1 (at most one blank line in a row) |
| `sort_imports` | true |
| `convert_do` | false |
| `indent_cases` | false |
| `inline_single_stmt_case` | false |
| `spaces_around_colons` | false |
| `space_single_line_blocks` | false |
| `align_struct_fields` / `align_struct_values` | true / true |
| `align_struct_declarations` / `align_constant_definitions` / `align_comments` | false / false / false |
| `multiline_composite_literals` | false |

- odinfmt sorts imports only within blank-line-separated groups (verified at OLS `d8188f0`), so `import-order` and the formatter agree.

## Naming

- **Cases:**
    - `snake_case`: lowercase ASCII letters and digits in words joined by single `_`, starting with a letter.
    - `Ada_Case`: ASCII words joined by single `_`, each starting with an uppercase letter or a digit; a word may be all caps, so `JSON_Value`, `Vec2` and `T` pass.
    - `SCREAMING_CASE`: uppercase ASCII letters and digits in words joined by single `_`, starting with a letter.
- A name with a non-ASCII letter never has a case. `_` alone is never a finding.
- Kinds, checked everywhere including bodies and `foreign` blocks:

| Declaration | Case |
| --- | --- |
| type (`struct`, `enum`, `union`, `bit_set`, `bit_field`, `distinct`, procedure type, any other type expression), enum member, parametric type (`$T`) | `Ada_Case` |
| procedure, procedure group | `snake_case` |
| value constant (`::` with a value, `#config(…)` included), parametric value (`$N: int`) | `SCREAMING_CASE` |
| variable (package-level or local), parameter, named result, struct, union or `bit_field` field, label, import alias, `foreign import` name | `snake_case` |
| `X :: Y`, `Y` a built-in type name (`int`, `rawptr`, `string`, …) | `Ada_Case` |
| `X :: Y`, `Y` any other name or `pkg.Name` | the case of `Y` |

## Later

- **Pure packages:** a `pure` status for packages with no global state that import only pure packages; rules `pure-import`, `pure-state`, `pure-allocators-tag`, `parse-unsupported`, and `config-missing-dir` for bad entries. Unknown: how often odx's parser lags the compiler on real code.
- **Ownership rules:** `allocator-param` (a public procedure returning allocated memory without an allocator parameter) and `require-results` (a public procedure returning an error without `@(require_results)`). Unknown: false positives on procedures returning views, and whether `odin doc` type info is stable enough to use.
- **Allocator coverage for `append`, maps and `tprint` inside `#+vet`:** depends on the Odin maintainers.

## Risks

- **`-warnings-as-errors`:** a warning in base, core or vendor becomes an error that can't be ignored. None appear in `fmt`, `os`, `encoding/json`, `odin/parser`, `thread`, `net` or `vendor:stb/image` at `dev-2026-09`; re-probe on each compiler bump.
- **Formatter drift:** a developer's odinfmt at a different OLS commit can disagree with odx's `format`. Teams pin OLS to the stated commit.
- **`cast-style` without type information:** telling `T(x)` from a procedure call needs to know `T` is a type; measure what odx can resolve from parsed declarations.
- **`name-case` on bindings:** C names in `foreign` blocks are findings; measure the ignore load on real bindings.
- **`line-length`:** string literals and comments the formatter can't wrap; measure the ignore load.
