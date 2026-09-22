<!-- odx:begin v1 -->
## odx

Policy fingerprint (generation 3): `3d463d5a5e0c4a0a4f59652e4519e9fa6246917029cf695321cc2b30733ae662`

Scope: all discovered project packages. Rules below are the union applicable to this selection; each rule retains its own scope.
- Package `docs/milestones`: role `(unmapped)`
- Package `docs/milestones/1-probe`: role `(unmapped)`
- Package `docs/milestones/2-probe`: role `(unmapped)`
- Package `docs/milestones/3-probe`: role `(unmapped)`
- Package `docs/milestones/4-probe`: role `(unmapped)`
- Package `docs/milestones/5-allocator-probe`: role `(unmapped)`
- Package `docs/milestones/5-probe`: role `(unmapped)`
- Package `docs/milestones/6-probe`: role `(unmapped)`
- Package `docs/milestones/7-adoption-probe`: role `(unmapped)`
- Package `docs/milestones/7-baseline-probe`: role `(unmapped)`
- Package `docs/milestones/7-cleanup-probe`: role `(unmapped)`
- Package `odx`: role `edge`

Run `odx check --json` for findings and coverage. Warnings fail with `--strict`; baselines soften findings and suppressions remove accepted findings. Exit 0 alone does not prove complete analysis. Guidance freshness checks policy synchronization, not source compliance. Baselines accept occurrences in unchanged source snapshots; checks never rewrite them. Use `odx baseline add`, `prune`, or `regen` for explicit maintenance.

Use `odx guidance check <markdown-file> [package-path]` to check this section and `odx guidance write <markdown-file> [package-path]` to regenerate it. Repeat the same scope. Rebuild after changing embedded builtin rules; project overrides load directly.

Configured policy (effective defaults included; no compiler run is implied):

```json
{"version":1,"roles":{"edge":["odx","odx/**"],"pure":[],"service":[]},"default_role":"","exclude":[".odx/**","rules/**","tests/**","evals/**","examples/**","vendor/**","build/**"],"disabled":{},"dependencies":{"edge":{"may_import":["pure","service","edge","core:*","vendor:*"],"deny":[]},"pure":{"may_import":["pure","core:*"],"deny":["core:os","core:os/*","core:net","core:sys/*","core:thread","core:sync","core:dynlib","core:c/libc","vendor:*"]},"service":{"may_import":["pure","service","core:*"],"deny":[]}},"odin":{"flags":["-vet","-vet-tabs","-vet-cast","-strict-style","-warnings-as-errors"],"forbidden_flags":["-no-bounds-check","-disable-assert","-no-type-assert","-ignore-unknown-attributes"],"required_flags":["-sanitize:address","-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true"],"collections":{},"custom_attributes":[],"allowed_vet_disables":[],"audit_file_tags":true,"explicit_allocators":"pure","declined":{"-vet-semicolon":"not evaluated; see odx doctor","-vet-style":"not evaluated; see odx doctor","-vet-unused-procedures":"not evaluated; see odx doctor","-vet-using-param":"not evaluated; see odx doctor"},"tagged_files_min":0,"version":"dev-2026-09","path":""},"errors":{"types":["Error"],"structural":true}}
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

### errors: Project-selected result acknowledgement and contextual error review
- **errors/R3** Exported non-test procedures whose named final result matches the configured error classification carry @(require_results).
  Scope: all roles, including unmapped packages
  Why: This project requires explicit result acknowledgement for selected APIs. The compiler rejects bare calls to attributed procedures but permits assigning any or all results to `_`.
  Instead of: Trusting callers to check the error result by convention.
  Correction: Add @(require_results) to the reported procedure declaration; callers must acknowledge its results, including by explicit discard.
  Check evidence: compiler_entities; compiler-selected exported procedure declarations, excluding @(test); canonical named final-result suffixes and optional structural classification from errors configuration; attribute presence only, no error-intent or caller-handling proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"require_attribute","attribute":"require_results","on":"exported_procs","from":"","names":[],"roles":[],"except_roles":[],"match":"","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"","mutable":false}`

Reviewer advice scope: roles pure, service, edge; this does not restrict the mechanical rules above.

Reader checks for errors (not enforced by `odx check`):

These questions guide review; `odx check` does not enforce them. Executable examples show
valid Odin, not proof of caller behavior. Neither example form below is a policy finding.

### Does the result communicate the information callers need?

Predicates and lookup success flags legitimately return bool. Use richer error values when
callers need failure details; a bool result alone does not establish an error-design defect.


### Do error domains fit their operations and callers?

Several error types in one package, a shared domain, and dependency error reuse can each be
appropriate. Consider whether callers can inspect and report useful details. No exactly-one
error-type or blanket string/any prohibition is enforced here.


### Is handling or propagation clear, and is explicit discard intentional?

Review recovery and ownership where the operation occurs. Explicit branches and `or_return`
are both valid propagation styles. `@(require_results)` establishes acknowledgement only;
it permits storing an unchecked result or explicitly discarding one. Review the consequences
of discard in context; no universal logging or process-exit requirement follows from Odin.

<!-- odx:end -->
