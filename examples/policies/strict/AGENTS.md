<!-- odx:begin v1 -->
## odx

Policy fingerprint (generation 4): `4a1caecd711cfd4904417e7f39d24d5d8844d4531d7d4326442b226236dd709d`

Scope: all discovered project packages. Rules below are the union applicable to this selection; each rule retains its own scope.
- Package `adapters`: role `adapters`
- Package `app`: role `app`
- Package `domain`: role `domain`

Run `odx check --json` for findings and coverage. Warnings fail with `--strict`; baselines soften findings and suppressions remove accepted findings. Exit 0 alone does not prove complete analysis. Guidance freshness checks policy synchronization, not source compliance. Baselines accept occurrences in unchanged source snapshots; checks never rewrite them. Use `odx baseline add`, `prune`, or `regen` for explicit maintenance.

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
  Effective selector: `{"kind":"vet_tag","roles":["domain"]}`

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
  Effective selector: `{"from":"dependencies.may_import","kind":"banned_import","roles":["domain"]}`
- **dependencies/R3** Domain source has no mutable package-scope value declarations, including conditional branches and foreign blocks.
  Scope: roles domain
  Why: Callers should supply mutable domain state explicitly.
  Instead of: Sharing mutable package state between domain operations.
  Correction: Move the state into a caller-owned struct and pass it as a parameter.
  Check evidence: native_ast; package-scope decl declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"at":"package_scope","kind":"pattern","match":"decl","mutable":true,"roles":["domain"]}`
- **dependencies/R4** Domain source contains no direct foreign imports or foreign blocks.
  Scope: roles domain
  Why: Place this application's direct foreign bindings in adapters.
  Instead of: Declaring direct foreign bindings inside the domain.
  Correction: Move the foreign declaration to an adapter and supply a capability to domain code.
  Check evidence: native_ast; package-scope foreign declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"pattern","match":"foreign","roles":["domain"]}`

### errors: Domain result acknowledgement for two chosen failure-name suffixes
- **errors/R3** Exported non-test domain procedures whose canonical named final result ends in Domain_Failure or Storage_Failure carry @(require_results).
  Scope: roles domain
  Why: Selected domain APIs require callers to acknowledge returned results.
  Instead of: Allowing bare calls to selected failure-returning APIs.
  Correction: Add @(require_results) to the selected procedure declaration.
  Check evidence: compiler_entities; compiler-selected exported procedure declarations, excluding @(test); canonical named final-result suffixes and optional structural classification from errors configuration; attribute presence only, no error-intent or caller-handling proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"attribute":"require_results","kind":"require_attribute","on":"exported_procs","roles":["domain"]}`

Reviewer advice scope: roles domain; this does not restrict the mechanical rules above.

Reader checks for errors (not enforced by `odx check`):

### Is explicit discard intentional?

The compiler permits assigning results to `_`. Review whether the caller should
recover, propagate, or deliberately discard them; attribute presence does not
prove meaningful handling.

<!-- odx:end -->
