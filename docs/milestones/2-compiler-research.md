# Milestone 2 compiler graph and foreign evidence

Research used `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`,
`dev-2026-09-nightly:a2fb372`, on macOS arm64. The installed native AST/parser
and `core/c/libc/signal.odin` are the syntax references. Scratch probes lived
under `/tmp/odx-m2-compiler`; no third-party parser or Python was used.

## Compiler graph observations

The probe application imported a local package under the alias `d` and
`core:fmt`. Additional files imported distinct local packages from
`platform_windows.odin`, a file with `#+build darwin`, and `extra_test.odin`.
All dependency packages contained only `Value :: 1` (with distinct constants
where useful). These commands succeeded:

```sh
odin check /tmp/odx-m2-compiler/app -show-import-graph -thread-count:1
odin check /tmp/odx-m2-compiler/app -target:windows_amd64 -show-import-graph -thread-count:1
```

| Input | Host graph | Windows graph |
| --- | --- | --- |
| Aliased local ordinary import | Present with canonical absolute path | Present |
| `#+build darwin` file import | Present | Absent |
| `_windows.odin` file import | Absent | Present |
| `_test.odin` ordinary import | Present | Present |
| `core:fmt` and its external dependencies | Present transitively | Present transitively |

The compiler normalized `/tmp` to `/private/tmp`. The host graph explicitly
contained `core/fmt -> core/os`, and subsequent `core/os` dependencies reached
`core/c/libc`. This is a concrete counterexample to treating an allowed
external package as proof that its implementation cannot reach a denied
package or foreign code. A source policy with external leaves must describe
only the imports at that boundary.

Ordinary `import` inside a `when` statement was rejected, even though the
native parser accepts this structure. The compiler recommended file suffixes
or build tags. Source-wide policy can inspect this syntax conservatively, but
must not claim it represents a valid active compiler graph.

`odin check ... -export-dependencies:json -export-dependencies-file:...` again
rejected both flags as supported only by run/build/test. DOT output therefore
remains the observed check interface. One warm probe reported 85.613 ms total
(39.433 ms parsing, 44.979 ms type checking). This small, single-entry graph is
not a project-scale benchmark or a reason to introduce caching.

## Foreign syntax is a separate category

Each of these packages passed `odin check <package> -no-entry-point
-show-import-graph -thread-count:1`:

```odin
package foreignonly
foreign import libc "system:System"
```

```odin
package foreignblock
foreign {
    nonexistent_symbol :: proc "c" () ---
}
```

```odin
package foreignconditional
when ODIN_OS == .Darwin {
    foreign import libc "system:System"
    foreign libc {
        puts :: proc "c" (s: cstring) -> i32 ---
    }
}
```

All three DOT results contained only the implicit runtime/intrinsics edge;
they contained neither a library edge nor a foreign symbol edge. A successful
check also does not prove a declared foreign symbol will link: the anonymous
block deliberately named a nonexistent symbol without calling it.

The native AST represents `Foreign_Import_Decl` and `Foreign_Block_Decl`
separately from `Import_Decl`. Foreign imports can carry multiple path
expressions. Blocks may use a named library or an anonymous library marker;
there need not be a matching foreign import in the file. Both constructs can
occur in `when` branches; the installed libc uses that form to choose the
system library. Counting only foreign imports misses anonymous blocks;
counting only blocks misses library imports without declarations. Counting
only top-level declarations misses conditional foreign syntax. Ordinary
imports can reach these constructs indirectly through local or external
packages. None of these facts proves a foreign procedure executes.

## Recommended bounded contract

Keep milestone 2 on a complete project source graph of ordinary imports.
Distinguish report selection from graph evidence. Define direct `may_import`
matching and transitive `deny` matching over that graph, with explicit
external leaves, and unavailable evidence for required excluded/missing local
packages. Preserve milestone 1's all-source domain, including generated,
platform, build-tagged, and test files; any narrower test traversal must be
declared explicitly and cannot certify general source reach.

Correct the built-in dependency rule and topic's assertions of compiler graph
analysis and foreign freedom. Ordinary import policy establishes neither
foreign-access freedom nor purity. Foreign syntax enforcement is a separate
policy decision requiring both native node kinds, conditional traversal, and
an external boundary. It is not supplied by `-show-import-graph`.

The alternative compiler graph has useful canonical resolution and external
closure, but changes the policy to one active target, requires successful
checking and DOT consumption, and still lacks foreign edges. Adding foreign
AST traversal now could enforce a narrow syntactic rule, but requires new
configuration semantics and a separate compatibility decision without demand
for that expansion. Neither alternative repairs selected-source consistency
as simply as retaining ordinary source imports with honest boundaries.

These are research results, not milestone acceptance results. Cross-platform
execution, every Odin target, compiler DOT stability, and graph performance
on large projects remain unproven. Revisit a compiler backend when a project
specifically needs active-target or external-closure policy; revisit foreign
checks when a precise configurable syntactic restriction is requested.
