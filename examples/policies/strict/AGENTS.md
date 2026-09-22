<!-- odx:begin v1 -->
## odx

Policy fingerprint (generation 2): `3f81e5660cb9d1b01f04f688e2ce715e984fa5ac64e4b4aa2607ba6f3807ef26`

Scope: all discovered project packages. Rules below are the union applicable to this selection; each rule retains its own scope.
- Package `adapters`: role `adapters`
- Package `app`: role `app`
- Package `domain`: role `domain`

Run `odx check --json` for findings and coverage. Warnings fail with `--strict`; baselines soften findings and suppressions remove accepted findings. Exit 0 alone does not prove complete analysis. Guidance freshness checks policy synchronization, not source compliance.

Use `odx guidance check <markdown-file> [package-path]` to check this section and `odx guidance write <markdown-file> [package-path]` to regenerate it. Repeat the same scope. Rebuild after changing embedded builtin rules; project overrides load directly.

Configured policy (effective defaults included; no compiler run is implied):

```json
{"version":1,"roles":{"adapters":["adapters","adapters/**"],"app":["app","app/**"],"domain":["domain","domain/**"]},"default_role":"","exclude":[".odx/**","cases/**","build/**"],"disabled":{},"dependencies":{"adapters":{"may_import":["domain","adapters","core:*"],"deny":[]},"app":{"may_import":["domain","adapters","app","core:*"],"deny":[]},"domain":{"may_import":["domain","adapters","core:*"],"deny":["core:os","core:os/*","core:net","core:net/*","core:sys/*"]}},"odin":{"flags":[],"forbidden_flags":[],"required_flags":[],"collections":{},"custom_attributes":[],"allowed_vet_disables":[],"audit_file_tags":true,"explicit_allocators":"all","declined":{},"tagged_files_min":0,"version":"dev-2026-09","path":""},"errors":{"types":["Domain_Failure","Storage_Failure"],"structural":false}}
```

### allocators: Domain files opt into the compiler's explicit-allocator directive
- **allocators/R1** Domain files contain #+vet explicit-allocators before the package declaration.
  Scope: roles domain; odin.explicit_allocators=all
  Why: Domain files opt into the compiler's explicit-allocator call-site vet check.
  Instead of: Leaving selected domain files outside the directive policy.
  Correction: Add #+vet explicit-allocators before package and satisfy affected compiler checks.
  Check evidence: native_tokens; file tag presence only; no allocator behavior or lifetime proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"vet_tag","attribute":"","on":"","from":"","names":[],"roles":["domain"],"except_roles":[],"match":"","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"","mutable":false}`

Reviewer advice scope: roles domain; this does not restrict the mechanical rules above.

Reader checks for allocators (not enforced by `odx check`):

### Is ownership clear to callers?

Document who retains or frees returned memory. Caller-owned arenas are legitimate;
a matching defer statement does not prove lifetime correctness. Neither this
advice nor the directive establishes allocation freedom.

### dependencies: This application's domain source boundaries and explicit state
- **dependencies/R2** Domain ordinary imports obey may_import and transitively avoid the configured OS/network deny list through included project source.
  Scope: roles domain; requires a dependencies policy for the package role
  Why: Domain dependencies must remain usable without the application's OS adapters.
  Instead of: Hiding a denied OS dependency behind an allowed intermediate adapter role.
  Correction: Remove the denied import chain and pass the required capability from app code.
  Check evidence: source_import_graph; recursive ordinary source imports with direct test allow exceptions; dependency *_test.odin edges omitted; unconfigured core/base/vendor collections are opaque leaves; required missing/excluded/unknown/outside project evidence is unavailable; no foreign or runtime effect guarantee
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"banned_import","attribute":"","on":"","from":"dependencies.may_import","names":[],"roles":["domain"],"except_roles":[],"match":"","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"","mutable":false}`
- **dependencies/R3** Domain source has no mutable package-scope value declarations, including conditional branches and foreign blocks.
  Scope: roles domain
  Why: Callers should supply mutable domain state explicitly.
  Instead of: Sharing mutable package state between domain operations.
  Correction: Move the state into a caller-owned struct and pass it as a parameter.
  Check evidence: native_ast; package-scope decl declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"pattern","attribute":"","on":"","from":"","names":[],"roles":["domain"],"except_roles":[],"match":"decl","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"package_scope","mutable":true}`
- **dependencies/R4** Domain source contains no direct foreign imports or foreign blocks.
  Scope: roles domain
  Why: Place this application's direct foreign bindings in adapters.
  Instead of: Declaring direct foreign bindings inside the domain.
  Correction: Move the foreign declaration to an adapter and supply a capability to domain code.
  Check evidence: native_ast; package-scope foreign declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"pattern","attribute":"","on":"","from":"","names":[],"roles":["domain"],"except_roles":[],"match":"foreign","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"","mutable":false}`

### errors: Domain result acknowledgement for two chosen failure-name suffixes
- **errors/R3** Exported non-test domain procedures whose canonical named final result ends in Domain_Failure or Storage_Failure carry @(require_results).
  Scope: roles domain
  Why: Selected domain APIs require callers to acknowledge returned results.
  Instead of: Allowing bare calls to selected failure-returning APIs.
  Correction: Add @(require_results) to the selected procedure declaration.
  Check evidence: compiler_entities; compiler-selected exported procedure declarations, excluding @(test); canonical named final-result suffixes and optional structural classification from errors configuration; attribute presence only, no error-intent or caller-handling proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"require_attribute","attribute":"require_results","on":"exported_procs","from":"","names":[],"roles":["domain"],"except_roles":[],"match":"","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"","mutable":false}`

Reviewer advice scope: roles domain; this does not restrict the mechanical rules above.

Reader checks for errors (not enforced by `odx check`):

### Is explicit discard intentional?

The compiler permits assigning results to `_`. Review whether the caller should
recover, propagate, or deliberately discard them; attribute presence does not
prove meaningful handling.

<!-- odx:end -->
