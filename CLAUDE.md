<!-- odx:begin v1 -->
## odx

Policy fingerprint (generation 1): `8d2b30682e04703b213a5ec53839e0a5d4319686fdd7cb9580217453210a9acf`

Scope: all discovered project packages. Rules below are the union applicable to this selection; each rule retains its own scope.
- Package `docs/milestones`: role `(unmapped)`
- Package `docs/milestones/1-probe`: role `(unmapped)`
- Package `docs/milestones/2-probe`: role `(unmapped)`
- Package `docs/milestones/3-probe`: role `(unmapped)`
- Package `docs/milestones/4-probe`: role `(unmapped)`
- Package `odx`: role `edge`

Run `odx check --json` for findings and coverage. Warnings fail with `--strict`; baselines soften findings and suppressions remove accepted findings. Exit 0 alone does not prove complete analysis. Guidance freshness checks policy synchronization, not source compliance.

Use `odx guidance check <markdown-file> [package-path]` to check this section and `odx guidance write <markdown-file> [package-path]` to regenerate it. Repeat the same scope. Rebuild after changing embedded builtin rules; project overrides load directly.

Configured policy (effective defaults included; no compiler run is implied):

```json
{"version":1,"roles":{"edge":["odx","odx/**"],"pure":[],"service":[]},"default_role":"","exclude":[".odx/**","rules/**","tests/**","evals/**","vendor/**","build/**"],"disabled":{},"dependencies":{"edge":{"may_import":["pure","service","edge","core:*","vendor:*"],"deny":[]},"pure":{"may_import":["pure","core:*"],"deny":["core:os","core:os/*","core:net","core:sys/*","core:thread","core:sync","core:dynlib","core:c/libc","vendor:*"]},"service":{"may_import":["pure","service","core:*"],"deny":[]}},"odin":{"flags":["-vet","-vet-tabs","-vet-cast","-strict-style","-warnings-as-errors"],"forbidden_flags":["-no-bounds-check","-disable-assert","-no-type-assert","-ignore-unknown-attributes"],"required_flags":["-sanitize:address","-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true"],"collections":{},"custom_attributes":[],"allowed_vet_disables":[],"explicit_allocators":"pure","declined":{"-vet-semicolon":"not evaluated; see odx doctor","-vet-style":"not evaluated; see odx doctor","-vet-unused-procedures":"not evaluated; see odx doctor","-vet-using-param":"not evaluated; see odx doctor"},"tagged_files_min":0,"version":"dev-2026-09","path":""},"errors":{"types":["Error"]}}
```

### dependencies: Project-defined ordinary import boundaries, checked against the project source graph
- **dependencies/R2** Ordinary imports obey the role's may_import and deny policy; deny also follows imports through included project production source, stopping at built-in collection boundaries.
  Scope: all roles, including unmapped packages; requires a dependencies policy for the package role
  Why: The compiler checks import validity; a project chooses allowed dependencies. Source import boundaries do not prove foreign-access freedom or runtime purity.
  Instead of: Letting any package import anything and discovering the OS dependency in a test that needs the world.
  Correction: Remove or restructure the reported import chain so direct imports satisfy may_import and no included dependency reaches a denied import under this role's policy.
  Check evidence: source_import_graph; recursive ordinary source imports with direct test allow exceptions; dependency *_test.odin edges omitted; unconfigured core/base/vendor collections are opaque leaves; required missing/excluded/unknown/outside project evidence is unavailable; no foreign or runtime effect guarantee
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"banned_import","attribute":"","on":"","from":"dependencies.may_import","names":[],"roles":[],"except_roles":[],"match":"","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"","mutable":false}`

### errors: Typed errors, @(require_results), or_return; never discard a failure
- **errors/R3** Exported procedures whose last result is an error type (a name in odx.json5 errors.types, an enum with a None/Ok variant, or a nil-able union) carry @(require_results).
  Scope: all roles, including unmapped packages
  Why: Only the attribute makes the compiler reject a discarded failure; -vet does not (`x, _ := f()` and a bare `g()` both pass). This is odx's convention, not a documented Odin one.
  Instead of: Trusting callers to check the error result by convention.
  Correction: Add @(require_results) to the reported procedure declaration; callers must then retain or explicitly discard its results.
  Check evidence: compiler_entities; compiler-selected exported procedure declarations, excluding @(test); inferred final error-result types and attribute presence; no caller-handling proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"require_attribute","attribute":"require_results","on":"exported_procs","from":"","names":[],"roles":[],"except_roles":[],"match":"","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"","mutable":false}`

Reviewer advice scope: roles pure, service, edge; this does not restrict the mechanical rules above.

Reader checks for errors (not enforced by `odx check`):

Conventions a reader enforces in review; `odx explain --checklist` lists them and
`odx self-test` compiles every block below, so the examples cannot rot. Nothing here fires.

### Exported procedures that can fail return an error type as the last result, not a bool.

A bool, and equally a single universal error type, is 'all the same degenerate value: error or not... a fancy boolean'. Callers cannot branch on it or report it.

A bool says that something failed, never what.



### Each package declares one Error enum or union; no string or any errors.

'Having an error value type defined per package is absolutely fine (and ergonomic too)'. A typed error is exhaustively switchable and greppable; strings and any are neither.

One switchable type per package; a `union` when it wraps several dependencies.



### Handle an error where it occurs when you can; when a package's operations genuinely chain, prefer or_return over hand-written `if err != nil { return }`.

'You make your mess; you clean it.' Local handling is the default; or_return is a per-package tool ('when a package needs it, it REALLY needs it') that keeps a chained happy path linear.

The hand-written form says the same thing in four lines that `or_return` says in one token.

<!-- odx:end -->
