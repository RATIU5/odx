# Milestone 1: analysis and coverage boundaries

Implemented against `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09`,
`dev-2026-09-nightly:a2fb372`, with doc format 0.3.2. Research preceded implementation
and independently examined [native parsing](1-parser-research.md),
[compiler exports](1-compiler-research.md), and a working
[Tree-sitter/ast-grep comparison](1-alternatives-research.md).

Status: complete. Milestone 2 remains the next implementation step.

## Decision

Retain Odin's native tokens/AST for source contracts and checked compiler exports
for the narrow type/attribute facts already consumed. Report their different
coverage explicitly. Do not add another parser or infer behavioral guarantees.

The alternative grammar was built and run with ast-grep 0.45.1. It supports useful
structural matching, but produced error nodes for compiler-valid anonymous struct
syntax and classified a mutable declaration differently inside a conditional.
Neither backend resolved shadowed calls. Native parsing avoids an additional
grammar and platform library while exposing the required declaration structure.
Its own failure cases require explicit handling: a malformed declaration can
return parser success with error diagnostics, and the native package convenience
function can crash on a missing package declaration.

Compiler-only analysis is another credible option: it selects active target
source and resolves types, but would silently drop inactive-source policies.
The inspected doc interface exports no call sites or resolved callees. Raw text
is sufficient only for explicitly textual policies; the comparison's comment and
string counterexamples defeat it for call restrictions. A full semantic or flow
engine has no justified requirement in this milestone.

Revisit this decision when a concrete project needs structural patterns the
selector vocabulary cannot reasonably express, a stable compiler semantic
interface becomes available, or editor recovery becomes a required workflow.

## What each check establishes

| Check category | Evidence and implemented boundary | Does not establish |
| --- | --- | --- |
| Role assignment | Selected package directories and config globs | Architectural purity or runtime effects |
| Allocator/vet/feature tags | Native file tag tokens and actual comments | Allocation behavior, ownership, or lifetime correctness |
| Dependency policy | Direct file-level ordinary imports with test-specific allow exceptions, config roles, and traversal through loaded project packages excluding `_test.odin` edges | Compiler-active dependency graph, foreign reach, or behavior inside external/excluded packages |
| Call pattern | Recursive AST walk, including nested procedures and both conditional branches; file import aliases normalized | Lexical scope resolution, indirect calls, or actual execution |
| Import/proc/decl/foreign patterns | Direct file-level declarations; grouped variable declaration currently reports its first name | Declarations inside conditional/foreign blocks, nested procedure declarations, or all source-level variants |
| Required attribute | Compiler-selected exported procedure declarations, excluding `@(test)`, with existing final-result error inference | Semantic error intent, complete caller handling, or arbitrary procedure-body properties |
| Compiler diagnostics | `odin check` under configured flags and compiler target selection | Running tests or checking every inactive configuration |

The existing selector and error-inference semantics are preserved. Their known
validation/meaning problems remain milestones 3 and 5. Completing an invocation
within the boundary above is not certification of broader policy prose.

Positive and negative evidence includes compiled exported procedures with and
without required attributes, mutable grouped declarations versus constants,
real comment tokens versus strings, and direct foreign imports versus blocks.
Adversarial cases include an imported alias and a locally shadowing struct field
both normalized to `os.exit`, inactive `when` calls, compiler-valid syntax rejected
by the alternative grammar, and a conditional import accepted by the native parser
but rejected by the compiler. The research notes preserve the commands and limits;
repository tests retain the safe-loader and export-validation counterexamples.

## Selection contract

Native analysis collects nonempty `*.odin` files in selected package directories.
It includes platform suffixes, build-tag-disabled files, `#+ignore`, generated
files, and `_test.odin` files. Both conditional branches remain syntax evidence.
Whitespace-only files are omitted by the native collector. A source generated on
disk is included; odx does not invoke a generator or infer missing generated code.

Package discovery applies configured directory exclusions and skips symlinks.
Native file collection within an already selected directory can follow file
symlinks. Excluded or external package code is outside the source scan, even when
the compiler type-checks it as a dependency. A path to a file selects its package,
not just that file; directory selection includes discovered descendant packages.

Compiler checks and entity export use compiler-selected files and branches for
the supplied flags (host target by default). Both check and doc reject ordinary
body errors, including in `_test.odin`; neither command executes test procedures.
Research also read successful host and Windows-target doc exports, but did not
execute tests on Windows. No other compiler release is supported by this proof.

`--since` selects existing changed/untracked Odin files and their packages. It
does not expand reverse dependencies, and config-only changes and deleted files
do not select a package. An empty selection now produces a report with no packages
and `complete: false`. It never claims full-project cleanliness. Defining stronger
incremental selection belongs to milestone 2.

## Machine and terminal contract

Schema 1 gains an additive `coverage` object:

- `selection`, `paths`, `since`, `topics`, and `exclude` describe the requested
  selection. Selection is `project`, `paths`, `since`, or `exemplar`; rule trials
  identify themselves as `rule_trial` in their terminal coverage footer.
- `source_scope` and `compiler_scope` describe the different evidence domains.
  `compiler` and `compiler_flags` record the configured invocation, not a claim
  that every listed flag succeeded or that every target was checked.
- `packages` lists selected directories and their collected source files.
  These are source inputs, not the compiler's active-file list.
- `checks` identifies package, rule, evidence, boundary, status, reason, and raw
  finding count. Counts precede suppression, baseline application, and truncation;
  they intentionally differ from final report counts.
- `complete` means every applicable requested check completed within its stated
  boundary and at least one package was selected. It is not a clean/violation
  result or a whole-project promise. Read findings and selection as well.

`complete` status with zero raw findings is clean within the stated boundary.
`failed` means required evidence could not be produced or source/compiler checking
failed. `unsupported` identifies an unhandled evidence boundary or format.
`skipped` identifies deliberately omitted or prerequisite-blocked checks.
`not_applicable` means role/check configuration excludes that package.
`not_run` is the internal initial state and is never evidence of success.

Terminal checks and hooks print a coverage summary and incomplete-check reasons.
A partial run with no findings says that completed checks had no findings rather
than printing an unqualified `ok`. Fast mode still exits 0 when its completed
checks pass, but marks compiler diagnostics and entity rules skipped and coverage
incomplete. Warnings, strict mode, suppression, and existing finding fields retain
their meanings.

Required unavailable evidence produces exit 2 when it is a tool/unsupported
failure. Source parse/type errors remain exit 1, with dependent checks skipped.
A nonzero compiler exit cannot become clean merely because its JSON contains only
warnings or no positions. Missing/unreadable doc artifacts, incompatible format,
invalid bounds/indices, or a missing requested package are explicit failures.
The old unproven newer-minor format cast is removed: exact 0.3.2 is required.

Scoped dependency policies with deny lists conservatively report `unsupported`
and exit 2 when the loaded project graph is partial; already discovered findings
remain visible. This prevents the reproduced false-clean result without claiming
to have solved milestone 2's graph construction. Direct-only policies without a
deny list do not require that transitive evidence.

Baseline shrinkage and explicit regeneration now require complete evidence.
Failed analysis cannot erase previously accepted debt. This small prerequisite
guard was brought forward from milestone 7 because otherwise the new failure
contract would still silently certify debt as resolved. Baseline identity and
adoption policy remain milestone 7 work. Rule trials also fail on unavailable
evidence instead of presenting an unexplained zero-match success.

## Compatibility, cost, and verification

JSON fields are additive under schema 1. Terminal output gains coverage text;
consumers needing a machine contract should use JSON. Exit-status changes are
intentional for formerly silent failures and incomplete required graph evidence.
Hooks retain their non-blocking exit behavior. No default rule semantics,
selection flags, third-party runtime, or cache was added.

The coverage row count scales with selected packages and active rules; export validation
scans only tables, strings, and indices consumed by entity checks. No recursive
decoder or second compiler invocation was added for coverage. These fixtures do
not establish latency on large projects. The format validator establishes safe
access to consumed fields, not authenticity or semantic truth of arbitrary input.

Validation commands use the reference compiler through mise and `ODX_ODIN`:

```sh
export ODX_ODIN=/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin
export PATH="/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09:$PATH"
mise run --force ci
```

CI includes the [CLI evidence probes](1-probe/main.odin), source-loader tests,
and real/corrupted doc-export tests, alongside existing rule fixtures, examples,
compiler redundancy audit, and self-check. Unix fake-compiler probes disclose a
skip on Windows. Toolchain/platform breadth, full selector semantics, compiler
graph consistency, and large-project performance remain unproven and are not
completion claims of this milestone.

Final acceptance run: `mise run --force ci` exited 0 on macOS arm64 with the
reference compiler. All 20 unit tests passed with address sanitization and memory
tracking, all five existing fixture projects and rule/reader blocks passed,
all four exemplar packages compiled, the compiler redundancy audit passed, and
all 49 CLI evidence assertions passed. Self-check covered 36 source files with
no findings and complete evidence for its stated boundaries. Doctor retained its
two pre-existing warnings (hook configuration and unused allocator-topic roles).

Acceptance is bounded: each current check category has an explicit evidence
source and limit; source-wide versus compiler-selected scope is visible in text
and JSON; skipped, failed, and unsupported evidence cannot certify a complete
clean run; the backend choice has comparative execution evidence and alternatives;
and no behavioral analysis, second parser, or flow subsystem was introduced.
