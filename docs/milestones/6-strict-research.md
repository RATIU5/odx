# Milestone 6 strict project research

Research completed 2026-09-21. This is a configuration and fixture recommendation,
not a claim that the implementation or acceptance suite has already passed.

## Demand and decision

The milestone 0 strict case is an application with `domain`, `adapters`, and `app`
packages. Existing corrected selectors can express all of its mechanical needs.
Use copyable project-local topic files with those role names, and retain ownership
as explicitly labeled reviewer advice. No engine extension is justified by this
case. This is a synthetic demonstration, not external adoption or an implementation
of the complete TigerStyle philosophy.

The two credible approaches are (1) project-local files and explicit configuration,
which are transparent and easy to customize but need maintained executable
examples, and (2) a versioned preset, which eases sharing but introduces version,
override, and migration contracts. Choose local files: two examples do not
establish a demand for preset distribution. A mandatory built-in expansion would
contradict the minimal project's independent choice.

Inspection: `odx/pattern.odin` supports package declaration and foreign syntax
selectors through conditional and foreign declaration containers;
`odx/applicability.odin` applies rule role filters consistently;
`odx/checks.odin` checks source import reach and explicit-allocator directives;
`rules/errors/R3.odx.md` documents canonical suffix classification and the new
structural opt-out. These existing contracts cover the selected needs. Do not add
naming, line counts, nesting metrics, or resolved-call promises without further
project demand and comparative research.

## Proposed configuration

Use `roles: {domain: ["domain", "domain/**"], adapters: ["adapters", "adapters/**"],
app: ["app", "app/**"]}` with no fallback role. Define explicit dependency policies
for all three. A useful adversarial demonstration allows domain to import the
adapter role directly but denies `core:os`, `core:os/*`, `core:net`, `core:net/*`,
and `core:sys/*` transitively. This proves that an allowed intermediate role does
not erase the originating domain restriction. State that project graph traversal
stops at opaque built-in collection boundaries.

Use local replacements for `dependencies`, `allocators`, and `errors` to ensure
built-in topic prose does not describe this project's role vocabulary incorrectly.
Whole-topic replacement is existing behavior; include precisely the selected rules.
Local `dependencies` can own source-boundary, mutable-state, and direct-foreign
rules. Local `errors` selects only domain packages, using
`errors: {types: ["Domain_Failure", "Storage_Failure"], structural: false}`.
The names are suffixes of canonical compiler type names, not exact declarations
or resolved error intent. Multiple domains are deliberately supported.

A local `vet_tag` rule should use `roles: ["domain"]` and configuration
`odin.explicit_allocators: "all"`. The current `"pure"` setting first restricts
matching to literal `pure`/`service` roles, so it cannot opt a custom domain role
in. `"all"` enables the matcher and its explicit role filter narrows it. This is
awkward but sufficient and must be explained in the copyable example. Adapters
and app packages need no tag. A reasoned file suppression is available for an
intentional individual exception, though unnecessary for the base demonstration.

## Rule and counterexample matrix

| Selected rule | Violation | Compliant example | Plausible false positive to prevent | Evasion or proof boundary |
| --- | --- | --- | --- | --- |
| Domain source import boundaries | Domain imports allowed adapter, adapter imports `core:os` | Domain accepts a caller-supplied capability; adapter uses OS facilities without a domain path | Direct adapter/app OS imports must remain permitted | A built-in collection can internally reach OS facilities; no runtime-effect claim. Full and selected-domain scans must report the same originating violation. |
| No domain mutable package declarations | `cache: Cache`, including package `when` branch | `limit :: 3`, a `Cache.count` field, local variables, or caller-owned `^Cache` | Mutable app state is allowed; fields and locals are not package state | Read-only binding can refer to mutable data, and calls can mutate caller state. This is not purity. All parsed conditional branches count, even inactive ones. |
| No direct domain foreign syntax | `foreign import` and a foreign block | Ordinary Odin declarations and comments/strings containing `foreign` | Foreign bindings in an adapter remain allowed | An ordinary imported package can contain foreign code. No transitive foreign-freedom guarantee. Foreign import and foreign block are separate reportable nodes. |
| Selected domain result acknowledgement | Exported procedure with final `Domain_Failure` or `Storage_Failure` result lacks `@(require_results)` | Attribute present; predicates, lookup bools, `Status :: enum {Ok, Waiting}`, and nil-able `Maybe_Value :: union {int}` remain unselected | No structural classification of optional/status values; same API shape outside domain is allowed | `_ = validate(...)` compiles. Private declarations, non-final results, anonymous types, and aliases follow documented existing scope; suffix collision can select an unrelated named type. No correct-handling guarantee. |
| Domain explicit-allocator file directive | Domain file lacks leading `#+vet explicit-allocators` | Directive before package; adapters/app omit it | Scratch use or replacing context are not exemptions; directive-like strings are not tags | Tag presence is the odx proof. Compiler checks affected explicit allocator arguments; append and indirect/internal allocations can still allocate. |

Ownership advice should say who retains or frees returned memory and accept
caller-owned arenas. Label it as reviewer advice; a textual `defer delete` or an
assertion count cannot prove lifetime correctness or useful assertions.

## Compiler evidence

The installed compiler `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`
accepted a temporary standalone package with the domain directive, caller-owned
mutable `Cache`, both attributed failure enums, unannotated predicate/lookup,
`Status` with `Ok`, nil-able union, private failure-returning procedure, local
variables, and explicit `_ = validate(&cache)`/`_ = store()` discards:

```sh
odin check /tmp/odx-m6-strict-research/valid.odin -file -no-entry-point
```

Exit 0 was observed. This establishes syntax and selected compiler semantics
only. The temporary path is research output, not the eventual committed fixture.
The implementation must retain the relevant examples in its executable suite.

## Concrete fixture and test plan

Create a copyable strict project with one passing domain, adapter, and app package,
its own `odx.json5`, local topics, and generated Markdown. Keep deliberate failures
outside that passing root or create them in isolated temporary copies so the
published example is runnable and root package discovery remains predictable.

1. Compile passing source and each source-valid violating variant with the pinned
   compiler. For missing attributes, compilation should succeed while policy
   fails; attributed bare-call negative compiler examples should fail as expected.
2. Check the strict project authoritatively and assert zero findings, no tool
   errors, and completed required evidence. Assert that custom role names appear
   and that no pure/service/edge restrictions or unselected reader advice leak.
3. Mutate each policy independently and require its exact rule ID and subject;
   assert a clean result after its repair. Independently test fields, local state,
   comments/string foreign text, optional/status values, and two failure domains.
4. Make a transitive domain-to-adapter-to-OS violation. Compare full output with
   selected domain output, including original root rule and graph boundary.
5. Put mutable state, foreign declarations, and an unannotated failure result in
   an adapter/app variant. Check they are silent for domain-only rules and that
   path-specific generated instructions omit those restrictions.
6. Omit the allocator tag only in a domain source file, then only in an adapter.
   Assert a finding only for domain, proving explicit opt-in with custom roles.
7. Generate whole-project and selected-package Markdown, verify freshness and
   deterministic output, change a local rule statement/scope, and require stale
   detection followed by successful regeneration. Assert clear reviewer labeling.
8. Run local rule executable examples where supported, then existing complete CI.
   Do not treat fast source-only checks as evidence that result-attribute checks ran.

Revisit engine changes only if the examples expose an actual inexpressible
requirement. In particular, exact per-procedure identity selection and richer
behavioral guarantees are outside this demonstration, not silently approximated.
