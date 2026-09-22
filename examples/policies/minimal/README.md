# Minimal parsing-library policy

Copy this directory, including `.odx`, to start a project with two source rules:
no mutable package declarations and no direct foreign declarations. The passing
`parser` package needs no architecture roles, allocator tag or result attribute.
Its enum and bool results are ordinary API choices.

From this directory, with `odx` and the supported Odin compiler on PATH:

```sh
odin check parser -no-entry-point
odx check --json
odx policy --write AGENTS.md
odx policy --verify AGENTS.md
```

Compilation and formatting remain project choices; configure compiler flags or
run odinfmt separately. Full odx checks also invoke the compiler; `--fast` omits
that evidence and reports its omission. Copying an example is a starting point,
not enrollment in a versioned preset.

The config disables `errors/R3` and file-tag auditing. Other current built-in
rules require roles or dependency configuration, absent here; allocator-tag
selection is explicitly off. Review applicability when adding roles or upgrading
the built-in catalog. Effective settings printed in guidance are configuration,
not additional rule statements. The project-owned rules live under
`.odx/topics/library`; edit their wording and selectors together, test them, then
regenerate instructions.

The `cases` directory contains complete alternative source files as `.odin.txt`
so they do not enter the passing project scan. To try one, copy this entire
example to a temporary directory and replace `parser/main.odin` there with the
case. The repository's policy integration test performs these substitutions.

| Case | Expected policy findings | Boundary demonstrated |
| --- | --- | --- |
| `mutable` | library/R1, once | Mutable package variable |
| `conditional_mutable` | library/R1, once | Inactive nested branches still count |
| `grouped_mutable` | library/R1, once | One finding per declaration, not per name |
| `foreign_import` | library/R2, once | Direct foreign import syntax |
| `foreign_block` | library/R2, twice | Import and foreign procedure block are separate declarations |
| `conditional_foreign` | library/R2, once | Inactive nested foreign import |
| `misleading_text` | None | Strings, comments, fields and local state are allowed |
| `file_tags` | None | Compiler-accepted opt-outs and enum results add no policy |

A dependency can use mutable state or foreign code without violating these rules
in its caller. If included in a full scan, that dependency's own declarations are
checked independently. Neither check proves purity, allocation freedom or any
runtime behavior. The foreign import example is compiled against the host C
library; other targets may require a different foreign library spelling.
