<!-- odx:begin v1 -->
## odx

Policy fingerprint (generation 5): `1a2a55475be0e0bfcce6103bcc690c2836e5b09191abe8fb291d05873213e7a5`

Scope: all discovered project packages. Rules below are the union applicable to this selection; each rule retains its own scope.
- Package `adapters`: role `adapters`
- Package `app`: role `app`
- Package `domain`: role `domain`

Run `odx check --json` for findings and coverage. Exit 0 alone does not establish complete analysis. Use `odx policy --verify <file>` to check freshness or `odx policy --write <file>` to regenerate; repeat the selected package path.

- **allocators/R1** [error] Domain files contain #+vet explicit-allocators before the package declaration.
  Scope: roles domain; odin.explicit_allocators=all
  Why: Domain files opt into the compiler's explicit-allocator call-site vet check.
  Correction: Add #+vet explicit-allocators before package and satisfy affected compiler checks.
  Evidence: native_tokens; file tag presence only; no allocator behavior or lifetime proof
  Effective selector: `{"kind":"vet_tag","roles":["domain"]}`

- **dependencies/R2** [error] Domain ordinary imports obey may_import and transitively avoid the configured OS/network deny list through included project source.
  Scope: roles domain; requires a dependencies policy for the package role
  Why: Domain dependencies must remain usable without the application's OS adapters.
  Correction: Remove the denied import chain and pass the required capability from app code.
  Evidence: source_import_graph; recursive ordinary source imports with direct test allow exceptions; dependency *_test.odin edges omitted; unconfigured core/base/vendor collections are opaque leaves; required missing/excluded/unknown/outside project evidence is unavailable; no foreign or runtime effect guarantee
  Effective selector: `{"from":"dependencies.may_import","kind":"banned_import","roles":["domain"]}`

- **dependencies/R3** [error] Domain source has no mutable package-scope value declarations, including conditional branches and foreign blocks.
  Scope: roles domain
  Why: Callers should supply mutable domain state explicitly.
  Correction: Move the state into a caller-owned struct and pass it as a parameter.
  Evidence: native_ast; package-scope decl declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Effective selector: `{"at":"package_scope","kind":"pattern","match":"decl","mutable":true,"roles":["domain"]}`

- **dependencies/R4** [error] Domain source contains no direct foreign imports or foreign blocks.
  Scope: roles domain
  Why: Place this application's direct foreign bindings in adapters.
  Correction: Move the foreign declaration to an adapter and supply a capability to domain code.
  Evidence: native_ast; package-scope foreign declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Effective selector: `{"kind":"pattern","match":"foreign","roles":["domain"]}`

- **errors/R3** [error] Exported non-test domain procedures whose canonical named final result ends in Domain_Failure or Storage_Failure carry @(require_results).
  Scope: roles domain
  Why: Selected domain APIs require callers to acknowledge returned results.
  Correction: Add @(require_results) to the selected procedure declaration.
  Evidence: compiler_entities; compiler-selected exported procedure declarations, excluding @(test); canonical named final-result suffixes and optional structural classification from errors configuration; attribute presence only, no error-intent or caller-handling proof
  Effective selector: `{"attribute":"require_results","kind":"require_attribute","on":"exported_procs","roles":["domain"]}`

### allocators: reviewer advice (not mechanically enforced)
Roles: domain

### Is ownership clear to callers?

Document who retains or frees returned memory. Caller-owned arenas are legitimate;
a matching defer statement does not prove lifetime correctness. Neither this
advice nor the directive establishes allocation freedom.

### errors: reviewer advice (not mechanically enforced)
Roles: domain

### Is explicit discard intentional?

The compiler permits assigning results to `_`. Review whether the caller should
recover, propagate, or deliberately discard them; attribute presence does not
prove meaningful handling.

<!-- odx:end -->
