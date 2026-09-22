# Milestone 6: independent minimal and strict policies

All three investigations finished before implementation:
[minimal project](6-minimal-research.md), [strict project](6-strict-research.md),
and [compiler/tool alternatives](6-alternatives-research.md). The requirements
are the synthetic library and application from milestone 0, revisited against
milestone 5's corrected semantics. This demonstrates expressibility and
deterministic behavior, not external adoption or agent productivity.

## Delivered projects

Copy either directory, including its `.odx` directory and configuration. No
engine change or preset installation is needed to customize their rules.

| Project | Selected policy | Deliberately allowed |
| --- | --- | --- |
| [Minimal parsing library](../../examples/policies/minimal/README.md) | Two local rules: no mutable package declarations and no direct foreign syntax. No architecture roles. | Enum and bool results without attributes, local state and struct fields, compiler-accepted file directives. |
| [Strict application](../../examples/policies/strict/README.md) | Five local domain rules: ordinary dependency boundaries, no mutable package state, no direct foreign syntax, selected result acknowledgement, and an allocator vet directive. Custom `domain`, `adapters`, `app` roles. | OS access, mutable process state, foreign syntax, and unannotated result APIs outside domain; optional/status results, multiple failure domains, and explicit result discard. |

Both supplied projects pass a full check and include managed `AGENTS.md`.
Deliberately failing source is stored as excluded `.odin.txt` cases; acceptance
tests apply it to temporary copies. Each local rule has executable fires/silent
examples, a rationale, correction, and a documented counterexample/boundary.
The project READMEs provide the complete case matrices and commands.

Minimal configuration disables `errors/R3`, turns allocator-tag selection off,
and opts out of implicit file-tag auditing. Other current built-in rules require
role/dependency configuration and are inapplicable. Built-in reader advice does
not apply to its unmapped package. Serialized inactive defaults in guidance do
not independently enable rules. Adding roles or upgrading the built-in catalog
requires reviewing applicability; this is not a future-proof catalog allow-list.

Strict configuration replaces the three built-in topics with local policies.
Each mechanical rule selects domain; app-scoped guidance excludes them. Setting
`explicit_allocators: "all"` enables the allocator matcher for custom roles,
while the local rule's role filter narrows its scope. Error classification uses
canonical suffixes `Domain_Failure` and `Storage_Failure`, with structural
inference disabled. Ownership and recovery remain labeled review advice.

## Problems found and changes selected

The existing selectors express both projects. Two authoring/configuration gaps
prevented a faithful demonstration:

1. File `#+feature` reason and `#+vet !x` allow-list audits ran regardless of
   selected rules. New `odin.audit_file_tags` defaults to `true`; `false` disables
   those two policies and their stale allow-list check. Coverage reports
   `not_applicable`, never a fictitious successful audit. The switch does not
   suppress compiler diagnostics, syntax errors, allocator R1, or invalid odx
   suppression metadata. `doctor` remains a separate recommendation/audit tool.
2. `rule test` copied the rulebook but silently rebuilt default policy settings,
   causing a minimal rule's compliant enum-return example to fail errors/R3 even
   though the project disabled it. Scratch examples now preserve effective
   compiler settings, error classification, disabled rules and dependency layers.
   Only the explicitly tested target is re-enabled for both fires and silent.

Scratch role globs are replaced with the example's `sample` package; existing
role names remain available to dependency policies. A role without a dependency
layer receives the historical `core:*`/`vendor:*` example allowance. Collections
are rebased to their original locations. Snippets remain self-contained examples,
not copies of the entire project; external dependencies do not gain an exemption
from graph evidence boundaries. Canonicalizing the scratch root preserves
discovery on macOS's temporary-directory symlinks.

The initialized config now explicitly records its structural-error and tag-audit
defaults, keeping the in-memory default and loaded configuration consistent.
Managed guidance snapshots already include effective configuration, so these
settings and local rule edits participate in freshness without a preset identity.

## Alternatives and missing capabilities

| Approach | Benefit | Cost and decision |
| --- | --- | --- |
| Copyable local topics and explicit configuration | Transparent, independently editable and executable | Updates are manual; selected because examples satisfy the demonstrated demand. |
| Versioned optional presets or a built-in allow-list | Convenient shared selection and upgrade identity | Needs selection, override and migration contracts; not justified by two examples. |
| Disable all current built-in IDs | Makes future role additions less surprising | More boilerplate and still tied to the current catalog; minimal uses proven applicability and one disabled ID. |
| Replace built-ins with empty topics for minimal | Uses existing whole-topic overrides | Requires meaningless files and still cannot disable implicit audits; rejected. |
| Turn off all vetting/compiler checks | Fewer findings | Loses language evidence and does not address independent policy selection; rejected. |
| Keep fixed default settings for rule snippets | Uniform isolated test environment | Tests different policies than the project actually selected; rejected. |

No new matcher, metric, parser, mandatory rule, or preset system was added.
Odin's `-disable-non-constant-globals` accepts mutable globals with constant
initializers, so it is not equivalent to the declaration ban. Compiler checks
own validity and attribute semantics; odinfmt owns layout. OLT's configurable
catalog may suit other projects; ast-grep offers structural matching with an
additional grammar/distribution contract. The alternatives record links primary
documentation and separates published capabilities from executed evidence.

Exact semantic identity selection, arbitrary naming patterns, nesting, and
procedure-size metrics remain unavailable or limited. Neither chosen project
requires them. Before adding size or nesting, define the unit (lines, statements,
or nodes), treatment of comments/branches/nested procedures, and false-positive
budget. Written call/type suffixes are not resolved identities. None of these
examples implies allocation freedom, purity, exhaustive cleanup, meaningful
assertions, or a mechanical encoding of TigerStyle.

## Validation and compatibility

`mise run policies` runs the retained [CLI acceptance probe](6-probe/main.odin)
and verifies both committed guidance files. It uses the same binary against
both temporary project copies, checks complete compiler evidence, exact finding
sets, counterexamples, full/scoped transitive findings, local rule tests, and
guidance scope/freshness. The probe is included in full CI.

Final `mise run --force ci` passed:

- 35 unit tests with address sanitization and memory tracking.
- 164 new policy assertions, including all 14 local fires/silent rule blocks.
- Existing milestone probes: 49 evidence, 113 architecture, 121 selector-contract,
  105 guidance, 58 error-semantics and 45 allocator-semantics assertions.
- All five fixture projects, built-in rule and reader examples, four exemplar
  packages, and the compiler redundancy audit.
- Both example `AGENTS.md` files and the repository's managed `CLAUDE.md` current.
- Repository self-check: 51 source files with complete evidence and no findings.

The initial integration run caught two shadowed variables in the new probe under
the full vet flags; those were corrected before the successful final run.
Doctor reports its two existing warnings about the edit hook and unused allocator
reviewer roles. `git diff --check` passed. Example source is excluded from the
repository's own policy scan and checked under each example's configuration by
the policies task. The ignored local roadmap status was updated separately.

The supported compiler is Odin `dev-2026-09-nightly:a2fb372` on Darwin arm64.
Other hosts and toolchain versions are unproven. Foreign fixtures use the host
C library spelling. External tool capability comparisons were not comparative
execution benchmarks.

Default project checking remains compatible. Explicit audit opt-outs change
only the requested checks. Local rule tests can now expose contradictions with
effective project policy that the old default-only scratch setup hid. Existing
rule IDs, selector semantics, report schema and managed marker syntax remain.
There is no added runtime dependency or cache. Revisit built-in selection if
catalog changes make minimal opt-outs burdensome, presets if independent users
need versioned reuse, and new AST capabilities only for demonstrated contracts.
