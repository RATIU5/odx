# Milestone 1 native parser evidence

Research used `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`,
version `dev-2026-09-nightly:a2fb372`. This is a single tested toolchain, not a
cross-version compatibility claim. The installed `core/odin/parser` and
`core/odin/ast` sources are the primary reference.

## Observed behavior

A small Odin probe parsed files through `parser.parse_file`, recorded diagnostics
and file counts, and traversed declaration nodes with `ast.inspect`. It proved:

| Input | Native parser evidence | Boundary |
| --- | --- | --- |
| A leading `#+vet explicit-allocators` | One token in `File.tags` | Tag presence does not prove allocator behavior. |
| A declaration comment | Preserved in `File.comments` and `Value_Decl.docs` | Comment text is not semantic evidence. |
| `@(private)` | One declaration attribute | Current exported checks only inspect declaration attributes. |
| `a, b: int` | One mutable declaration with two names | Existing declaration matching reports the first name. |
| `Alias :: int` | Ordinary immutable value declaration | No resolved type identity follows from syntax alone. |
| A nested procedure literal | Both outer and nested literals visited | Existing proc selector only inspects direct file declarations. |
| `when false { ... } else { ... }` | Both branches preserved and visited | A walk does not establish active-target execution. |
| Foreign import and foreign block | Separate AST node categories | Neither is an ordinary import edge. |
| Renamed import | Import alias and path preserved | Alias normalization does not resolve local shadowing. |

A compiler-valid example contains both a local `os.exit` function-valued field
and `alias.exit`, where `alias` imports `core:os`:

```odin
package example
import alias "core:os"
f :: proc() {
    os := struct {exit: proc(int)}{exit = proc(code: int) {}}
    os.exit(1)
    alias.exit(1)
}
```

`odin check example.odin -file -no-entry-point` succeeds. Existing call matching
normalizes the import alias to `os.exit`, and also sees the unrelated local
`os.exit` spelling. That is a syntactic policy with import-name normalization,
not a resolved-callee policy. Procedure values and indirect calls remain outside
any claim of complete call-graph coverage.

## Source selection

`parser.collect_package` in `core/odin/parser/parse_files.odin` globs `*.odin`,
reads the matching files, and skips whitespace-only files. It does not apply
platform suffixes, build tags, generated-source comments, or test conventions.
A probe package contained `main.odin`, `platform_windows.odin`,
`generated.odin`, `testing_test.odin`, and an `ignored.odin` with `#+ignore`.
All five appeared in the parsed package. Unknown identifiers in the Windows and
ignored files did not prevent the host compiler check from succeeding.
Generated source and test-named files are included by the source scanner.
Directory exclusions and package selection are odx responsibilities.

`core/odin/parser/file_tags.odin` exposes parsed build tags and matching helpers,
but its subtarget handling has an explicit TODO. Reimplementing compiler file
selection with these helpers would require additional evidence; retaining and
labeling source-wide selection is simpler and more honest.

## Failure and disagreement counterexamples

The native parser accepts this with zero syntax errors:

```odin
package example
when false {
    import "core:os"
}
```

The installed compiler rejects it: imports cannot occur inside a `when`
statement; use filename suffixes or build tags. A successfully produced syntax
tree therefore does not establish compiler validity.

For this malformed file, `parse_file` returns `true`, emits two diagnostics, and
sets `syntax_error_count` to two:

```odin
package example
broken :: proc( {
```

`parse_file` returns true after declaration parsing even if that parsing emitted
errors. A caller must inspect diagnostics or error counts as well as the return
value. Syntax findings on recovered trees cannot certify complete coverage.

For a file containing only `broken :: 1`, `parse_file` returns false without a
package declaration. The convenience `parse_package_from_path` subsequently
dereferences `file.pkg_decl.name` and the probe exits with signal 11 (status 139).
A safe loader must avoid that dereference, retain an analysis failure, and keep
the process alive. Collection can also return an allocated package with false
success after an I/O failure; checking only a non-nil package is insufficient.

## Implementation implications

Retain the native parser for source policies. Preserve current selector behavior
while documenting that call traversal is recursive, whereas declaration,
procedure, import, and foreign selectors inspect direct file declarations.
Do not label top-level-only enforcement as complete structural conformance.
Changing those selectors belongs to a separately tested rule-semantics change.

Use source-wide file selection for native checks, explicitly including inactive,
platform-specific, generated, and test-named source. Treat compiler evidence as
host/configuration-dependent. Failed parse or collection must be visible as
failed evidence, not a clean rule result. Track unavailable compiler evidence
separately. Do not infer resolved-call identity, execution, purity, or allocation
freedom from syntax.

The temporary probe and fixture commands were `odin run probe.odin -file --
fixture.odin`, `odin run probe.odin -file -- package fixture`, and `odin check
fixture -no-entry-point`. Regressions for shipped guarantees should retain the
counterexamples in repository tests rather than depend on temporary probe files.
