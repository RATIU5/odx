# Milestone 5: existing policies within their proven semantics

All three research investigations finished before implementation:
[errors](5-error-research.md), [allocators](5-allocator-research.md), and
[declarations and policy wording](5-policy-research.md). Research used Odin
dev-2026-09 revision `a2fb372` on Darwin arm64. The installed compiler/runtime
and official Odin documentation are the primary evidence; the research records
separate compiler acceptance from policy findings and behavioral guarantees.

## Problem and selected contracts

Four active built-in rules remain. No retired rule is reactivated and no new
built-in policy is introduced. The changes repair misleading explanations,
an unavoidable structural error heuristic, and missed package declarations.

| Rule | Enforced fact | Legitimate counterexample or limit |
| --- | --- | --- |
| allocators/R1 | Selected files have the parsed explicit-allocator vet directive before `package`; leading comments are allowed | Explicit scratch allocation and context replacement do not create automatic exemptions. A tagged zero-initialized dynamic array can still allocate through append. |
| dependencies/R2 | Ordinary imports satisfy the configured source-graph boundary | Foreign syntax, external-library effects, and runtime purity are not established. Existing direct test allowances and opaque built-in collection boundaries remain. |
| dependencies/R3 | Applicable pure/service packages contain no mutable package-scope value declarations, including conditional branches and foreign variables | Local variables and nested procedures are outside package scope; constants, imported state, context, and calls may still expose effects. Grouped variables produce one finding. |
| errors/R3 | Compiler-exported non-test procedures with a classified named final result have `@(require_results)` | Explicit discards and unchecked retained values compile. Type shape and suffix are project conventions, not proof of failure intent. |

`errors.types` remains a list of canonical type-name suffixes, default `["Error"]`.
`errors.structural` defaults to `true` for compatibility. Setting it to `false`
turns off enum `None`/`Ok` and nil-able union inference; setting `types: []` as
well classifies nothing. Empty or whitespace-only suffixes are invalid, avoiding
an accidental match-every-name convention. Alias spellings resolve to the
compiler's canonical name; distinct types retain their name. Anonymous results,
non-final error results, private procedures, and excluded test procedures are
outside this rule's selection. Structural matching examines the exported named
type's underlying shape, without inferring application intent.

Allocator parameters, ownership, scratch reset boundaries, and deliberate context
interception remain review decisions. No machine exemption is inferred from an
assignment or an allocator's spelling. Existing role selection, disabling, and
reasoned ignores express project exceptions. The required directive checks
affected default allocator arguments in compiler diagnostics; it is neither
universal allocation detection nor a lifetime guarantee.

Error reviewer guidance now allows predicates and lookup booleans, multiple
legitimate error domains in a package, and both explicit propagation and
`or_return`. Examples compile; their compilation does not enforce review advice.
The attribute rejects bare calls, including deferred bare calls, while allowing
`_ = f()` and `x, _ := g()`. Nothing here proves correct failure handling.

## Alternatives and tradeoffs

| Decision | Credible alternative | Why this choice |
| --- | --- | --- |
| Preserve suffix matching with a structural opt-out | Require exact package-qualified error identities | Minimal compatible configuration; exact identities need additional alias, qualification, and migration contracts. Revisit when real policies need stronger disambiguation. |
| Traverse package declaration containers | Narrow R3 to direct file-level declarations | Conditional globals are valid Odin and an easy evasion of the existing promise. Scope-aware traversal avoids false positives on local state. |
| Keep allocator enforcement directive-only | Infer exemptions or require a universal allocator signature | Context assignments and parameter names cannot prove ownership or lifetime. Explicit project exceptions are predictable. |
| Keep intent-dependent choices as contextual review advice | Turn anti-bool, one-domain, or propagation style preferences into rules | No demonstrated project requirement or mechanical proof justifies those universal restrictions. |

Traversal is linear in source declaration containers and includes inactive arms,
consistent with existing all-source policy coverage. No parser, cache, effect
analysis, or external dependency was added. The error opt-out can reduce findings;
expanded declaration coverage can add previously missed findings. Existing rule
IDs, baseline subjects, report schema, and suppression syntax remain stable.

The shared traversal also reaches foreign procedure declarations in public
`pattern` selectors. Their `exported` filter remains syntactic: it excludes a
declaration's own private attribute, not inherited file/block privacy. The
compiler-entity error rule uses compiler exports instead. Ordinary imports inside
`when` are rejected by the supported compiler; visiting a parsed node does not
certify language validity. Source findings and compiler diagnostics retain their
separate evidence boundaries.

Guidance generation revision advances to 2 because selector interpretation changed.
Effective configuration includes `errors.structural`; configuration or embedded
policy changes invalidate managed Markdown. Regeneration is explicit after a
fresh build. Scoped guidance continues to use shared rule applicability.

## Acceptance and limits

The retained [error CLI/compiler probe](5-probe/main.odin) and
[allocator CLI/compiler probe](5-allocator-probe/main.odin) exercise semantic
counterexamples through the real compiler and command interface. Declaration
unit tests cover package scope, inactive branches, foreign variables, grouped
declarations, and local-state exclusions. `mise run semantics` runs the new
compiler/CLI probes as part of CI.

Final `mise run --force ci` passed on the pinned compiler:

- 34 unit tests with address sanitization and memory tracking.
- 58 error/configuration/guidance/compiler assertions and 45 allocator assertions.
- Milestone 1 evidence, milestone 2 architecture, milestone 3 contracts, and
  milestone 4 guidance probes; 49, 113, and 121 assertions in the first three.
- All five fixture projects, active rule and reader examples, four exemplar
  packages, and the compiler redundancy audit.
- Fresh managed `CLAUDE.md`, verified by the guidance CI task.
- Self-check: 50 source files in eight packages, complete evidence, no findings.

Doctor retains its two pre-existing warnings: the local hook is not configured
to run `odx hook edit`, and allocator reviewer roles are unused by this repository.
`git diff --check` passed. The local ignored `ROADMAP.md` status was updated;
the tracked milestone record and README preserve the delivered contract.

The supported host/compiler is the acceptance boundary. Generic specialization,
arbitrary compiler flag combinations, other targets, runtime allocation effects,
all-path cleanup, and external-project adoption are not newly proven. Revisit
these choices when an actual project needs exact semantic identities,
compiler-selected declaration policies, or bounded behavioral analysis.
