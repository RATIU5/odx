# Milestone 1: native parser versus Tree-sitter/ast-grep

Research date: 2026-09-21. This comparison retains native Odin parsing for
structural policies. Tree-sitter is a credible alternative for reusable patterns
and editor searches, but the observed grammar disagreement adds a correctness
and distribution burden without providing resolved calls or target selection.
No second parser is required by the policies studied here.

## Recorded environment and reproducible comparison

- Odin: `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`,
  `dev-2026-09-nightly:a2fb372`.
- Installed ast-grep: `0.45.1`.
- [Odin Tree-sitter grammar](https://github.com/tree-sitter-grammars/tree-sitter-odin),
  commit `d2ca8efb4487e156a60d5bd6db2598b872629403`, package version `1.3.0`.
- Host execution only; no claims about other architectures or older toolchains.

The [valid probe](1-alternatives/probe.odin.txt) and
[malformed probe](1-alternatives/malformed.odin.txt) are preserved as text to avoid
including them in repository compilation. Copy them to `probe.odin` and
`malformed.odin` in a temporary checkout of the grammar. The valid probe passes:

```sh
/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin check probe.odin -file -no-entry-point
```

Build the grammar's committed C sources (no generator installation needed):

```sh
cc -shared -fPIC -O2 -I src src/parser.c src/scanner.c -o odin.dylib
```

Use this `sgconfig.yml` in that checkout:

```yaml
ruleDirs: []
customLanguages:
  odin:
    libraryPath: odin.dylib
    extensions: [odin]
    expandoChar: _
```

The registration follows the [ast-grep custom-language interface](https://ast-grep.github.io/advanced/custom-language.html).
Run the comparison from that directory:

```sh
ast-grep run --lang odin --pattern 'os.exit($$$ARGS)' probe.odin
ast-grep run --lang odin --kind variable_declaration probe.odin
ast-grep run --lang odin --kind var_declaration probe.odin
ast-grep run --lang odin --kind assignment_statement probe.odin
ast-grep run --lang odin --kind foreign_block probe.odin
ast-grep run --lang odin --kind import_declaration probe.odin
ast-grep run --lang odin --kind ERROR --json=compact probe.odin
ast-grep run --lang odin --pattern 'os.exit($$$ARGS)' malformed.odin
ast-grep run --lang odin --kind ERROR malformed.odin
```

## Observed results and adversarial cases

| Policy/example | Observed ast-grep result | Consequence |
| --- | --- | --- |
| Call spelled `os.exit` | Matches `os.exit(1)`, `(4)`, and `(7)` | Includes the inactive `when false` procedure, direct call, and shadowed local field call. Syntax matching cannot promise resolved standard-library identity. |
| Comment/string containing the same spelling | No match | Structural matching avoids this basic raw-text false positive. |
| Renamed import `platform.exit(5)` and procedure alias `alias(6)` | No match | Correct for a spelling contract; misses semantic identity. |
| Grouped mutable declaration `a, b := 1, 2` and attributed `hidden := 3` | `variable_declaration` matches | Attributes and grouped identifiers are retained. |
| Typed mutable declaration `typed: int` | Requires `var_declaration` | One mutable node kind is insufficient. |
| Mutable declaration inside `when false` | `assignment_statement` matches `inactive := 1`; the exact `--pattern 'inactive := 1'` does not | The standalone pattern is parsed as `variable_declaration`, demonstrating a concrete context-sensitive pattern mismatch. Scope and declaration classification still need policy-specific logic. |
| Ordinary imports and `foreign import libc` | All are `import_declaration` | Foreign imports need an explicit syntactic discriminator. |
| `foreign libc { puts :: proc(...) --- }` | `foreign_block` matches | This is a separate construct from foreign imports. |
| Compiler-valid anonymous struct containing a procedure field | Two `ERROR` nodes: `struct { exit: proc(int) }` and `exit: proc` | Proven disagreement with the selected compiler. A match found elsewhere does not certify complete parsing. |
| Malformed procedure body | Still matches `os.exit(1)` and separately exposes an `ERROR` | Recovery can be useful for editing, but ordinary successful search is not evidence of valid or completely analyzed source. |

The shadowing example remains a useful spelling counterexample even though the
alternative grammar reports errors around its declaration: it demonstrably
returns the shadowed call as a match. It cannot serve as proof that the grammar
fully understood that declaration. The native parser's structural proof is
recorded separately in this milestone.

## Credible approaches and decision

**Native Odin parser plus narrowly scoped compiler facts.** Already linked into
odx; the selected installation's `core/odin/ast/ast.odin` exposes `Value_Decl`
with `names`, `is_mutable`, attributes, and comments, and separate
`Foreign_Block_Decl` and `Foreign_Import_Decl` records. This directly supports
explicit structural contracts without translating another grammar's node
vocabulary. Traversal and scope still need tests: the AST preserving a node is
not proof that an existing selector visits it. Compiler validity and exported
entity/type facts supplement syntax only where that interface actually supplies
the required evidence. This is the selected approach.

**Tree-sitter with ast-grep custom-language rules.** Demonstrated working, with
convenient call patterns, node-kind searches, comment exclusion, and recovery.
It can support project-authored structural searches. Integration requires a
pinned grammar, native library distribution per supported platform, runtime/ABI
compatibility checks, and a strategy for compiler/grammar disagreements. The
current experiment compiled committed C directly; regeneration would additionally
require the grammar's generator tooling. Neither the grammar nor custom-language
registration supplies name resolution, active build selection, or package graph
completeness. The valid-input error and context-sensitive pattern mismatch are
concrete costs for adopting it as odx's enforcement backend.

**Raw source matching** remains appropriate for explicitly textual contracts
such as required header spelling. It is insufficient for these structural
policies: the probe's comment and string contain apparent calls. Adding lexical
or syntactic exclusions would recreate work already available in the parser.

No benchmark or broad grammar-conformance campaign was performed. This bounded
comparison establishes working integration and specific counterexamples, not
that every native-parser case succeeds or that Tree-sitter is generally inferior.
Revisit the backend decision if a concrete required policy needs structural
patterns that the current selector vocabulary cannot reasonably express, or
editor recovery becomes a product requirement; repeat these compiler-validity
and malformed-input comparisons before changing enforcement.
