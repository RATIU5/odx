# Milestone 2: architecture evidence and incremental reporting

Implemented on 2026-09-21 using the mise installation of Odin
`dev-2026-09-nightly:a2fb372`, on macOS arm64. Research completed before
implementation: [source graph](2-graph-research.md),
[incremental workflows](2-incremental-research.md), and
[compiler/foreign evidence](2-compiler-research.md).

## Problem and decision

The same package lost a transitive dependency finding when selected by path.
Milestone 1 exposed the missing evidence but still could not produce the
finding. Unassigned collection packages also prematurely ended traversal;
excluded dependencies could appear clean. Incremental selection omitted
unchanged importers, deleted files, and policy-only changes.

Each invocation now parses all discovered project packages once and builds a
fresh ordinary-import adjacency graph. Explicit paths select reporting packages,
not the available dependency evidence. Compiler checks, entity checks, file
counts, suppressions, and findings still apply to reporting packages. Required
reachable failures invalidate architecture evidence; unrelated failures do not.

Alternatives considered:

| Approach | Benefit | Cost / decision |
| --- | --- | --- |
| Complete discovered source graph | One resolution model; straightforward full/scoped consistency | More parsing for small scopes; selected here |
| On-demand dependency closure | Less parsing for disconnected projects | Loading, canonical identity, failures and reverse impacts complicate correctness; defer |
| Compiler graph | Canonical active-target imports and external closure | Different source domain, requires checking, DOT interface, no foreign edges; not a substitute |
| Persisted graph | Potentially lower latency | Source/config/toolchain/deletion invalidation; measurements do not justify it |

For incremental reporting, reverse-dependency expansion could reduce work, but
deletions require historical edges and policy edits can affect every package.
The selected alternative is full current-project reporting after any relevant
change. No graph cache or historical graph is introduced.

## Exact contract

`may_import` permits direct ordinary imports by target project role or import
pattern. Patterns are exact strings, except a trailing `*` matches a prefix.
Existing `base:*` and `core:testing` allowances and own-test allowances for
`core:testing`, `core:log`, and `core:fmt` remain; an explicit deny wins.

`deny` matches direct imports and imports reached through discovered project
packages. Package identity uses canonical filesystem paths, independently of
role assignment. Configured collections take precedence over built-in names.
Import literals are decoded with the installed `core:strconv.unquote_string`.
Unshadowed built-in collection subpaths are also cleaned before policy matching:
the compiler accepts `core:fmt/../os`, which must not bypass a `core:os` deny.
Original decoded spelling remains the direct finding subject. A built-in path
escaping its collection produces unavailable evidence.

Edges are collected by the native AST visitor, including inactive and generated
source and conditional syntax. The compiler rejects ordinary imports nested in
`when`, but native source checking still inspects them; compiler validity is
separate evidence. Own test-file imports are checked. Dependency `_test.odin`
edges are omitted from transitive production reach, preserving existing policy.
Parsing is conservative at package granularity: a malformed dependency test can
still make the dependency's parse evidence unavailable.

Unconfigured `core:`, `base:`, and `vendor:` imports are explicit opaque leaves.
Their implementations are not inspected, their existence is compiler evidence,
and allowing `core:fmt` does not establish absence of `core:os` effects. Missing
or excluded project packages, unknown collections, and relative/configured
collection targets outside the project are unavailable evidence, not clean
leaves. Such direct resolution failures exit 2; reachable failures also exit 2
when a nonempty deny policy requires traversal. Empty deny lists require only
direct permission/resolution evidence.

Foreign imports and foreign blocks are separate AST categories. Neither is an
ordinary import edge; neither is exported as a foreign edge by the observed
compiler graph. R2 and its topic now explicitly avoid foreign-access, purity,
and runtime-effect guarantees. No retired foreign rule is restored.

Breadth-first traversal selects a shortest package chain per direct import,
breaking ties by sorted file order and AST source order. Cycles terminate;
denied destinations are sorted before emission. Existing ordinary finding
subjects are retained. New findings through previously missed edges are an
intentional compatibility correction.

## Invocation and coverage

- Full checks report all discovered packages; file/directory checks report the
  selected packages with the same architecture evidence and findings.
- `--since REF` uses NUL-delimited Git paths, both rename endpoints, and untracked
  files. Any `.odin`, root `odx.json5`, root `odx.baseline`, or `.odx/topics/**`
  change triggers full current-project reporting, including unchanged importers.
  Deleted inputs remain triggers. Changes are relative to the project directory,
  including when it is nested in a larger Git worktree.
- No relevant changes means an empty report with `coverage.complete: false`;
  it is not certification of the current project. Invalid Git references fail.
- File and batch hooks use the same trigger policy, report the full project,
  retain compiler diagnostics, and run available native checks even when the
  compiler fails. Hook findings remain advisory with exit 0, limited to 50;
  compiler entity rules remain omitted. Unavailable Git discovery falls back
  to full reporting.
- Schema 1 gains `coverage.graph_packages` and `coverage.selection_reason`.
  `coverage.packages` remains the reporting selection. Per-rule graph failures
  have status/reason and tool errors. Complete evidence never means no findings.
- Incremental and hook runs retain the existing no-baseline-shrink guard even
  when their triggered reporting covers the project. Explicit partial scans and
  failed evidence cannot shrink baselines either.

## Evidence and limits

The retained Odin CLI runner in [2-probe](2-probe/main.odin) checks the original
full/file/directory counterexample; unassigned collections; canonical symlinks;
missing, excluded and unknown dependencies; own versus dependency tests;
inactive source; unrelated versus reached malformed source; cycles; diamond
witnesses; decoded literals; dependency-only changes; configuration changes;
deletion/rename; and hook behavior. The milestone 1 runner now expects a real
scoped finding and confirms hooks preserve compiler errors while running source
checks. These assertions fail against the previous behavior.

Final `mise run --force ci` passed 20 unit tests with address
sanitization/memory tracking, all five fixture projects, rule/reader examples,
four exemplar packages, compiler redundancy audit, 49 milestone 1 assertions,
113 milestone 2 assertions, and the self-check (38 files, four packages). Doctor
retains two pre-existing warnings about hook configuration and unused role
applicability. The final regressions include direct/transitive built-in path
normalization, collection escapes and shadowing, outside-root collections,
conditional ordinary imports, batch hooks, and local-policy-only changes.

The 102-package synthetic benchmark includes subprocess startup, graph parsing,
native checks, and JSON output, but omits compiler checks. Three-run means were
50.11 ms full and 19.11 ms scoped in an isolated probe, and 54.66/21.59 ms during
concurrent CI. The final expanded CI run measured 59.21/23.41 ms. Scoped scans
still parse the graph; their smaller reporting and
output cost less. These are observations, not latency guarantees. Large real
projects, filesystem races during scans, other host operating systems, and all
Odin targets remain unproven. Full-project compiler work after hook edits may
cost substantially more than native graph parsing.

Revisit dependency closure or caching only after representative projects show
unacceptable uncached latency. Revisit a compiler backend for a requested
active-target/external-closure policy, and foreign syntax for an independently
specified policy covering both foreign node categories and boundary behavior.
