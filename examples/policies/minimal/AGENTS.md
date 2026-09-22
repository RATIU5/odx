<!-- odx:begin v1 -->
## odx

Policy fingerprint (generation 2): `ef4dbd087d0575bd8677190f67d16c6b600684997b37f2def41c69f0342017ab`

Scope: all discovered project packages. Rules below are the union applicable to this selection; each rule retains its own scope.
- Package `parser`: role `(unmapped)`

Run `odx check --json` for findings and coverage. Warnings fail with `--strict`; baselines soften findings and suppressions remove accepted findings. Exit 0 alone does not prove complete analysis. Guidance freshness checks policy synchronization, not source compliance.

Use `odx guidance check <markdown-file> [package-path]` to check this section and `odx guidance write <markdown-file> [package-path]` to regenerate it. Repeat the same scope. Rebuild after changing embedded builtin rules; project overrides load directly.

Configured policy (effective defaults included; no compiler run is implied):

```json
{"version":1,"roles":{},"default_role":"","exclude":[".odx/**","cases/**","build/**"],"disabled":{"errors/R3":"This library chooses only two local source restrictions."},"dependencies":{},"odin":{"flags":[],"forbidden_flags":[],"required_flags":[],"collections":{},"custom_attributes":[],"allowed_vet_disables":[],"audit_file_tags":false,"explicit_allocators":"off","declined":{},"tagged_files_min":0,"version":"","path":""},"errors":{"types":["Error"],"structural":true}}
```

### library: Two source restrictions for a small parsing library
- **library/R1** Declare no mutable package-scope values, including inactive when branches and foreign blocks.
  Scope: all roles, including unmapped packages
  Why: Callers own parsing state and can use independent instances of this library.
  Instead of: A package variable shared by otherwise independent callers.
  Correction: Move the variable into a caller-owned struct or procedure-local value.
  Check evidence: native_ast; package-scope decl declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"pattern","attribute":"","on":"","from":"","names":[],"roles":[],"except_roles":[],"match":"decl","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"package_scope","mutable":true}`
- **library/R2** Declare no direct foreign imports or foreign blocks, including inactive when branches.
  Scope: all roles, including unmapped packages
  Why: The parsing library keeps its own source independent of foreign bindings.
  Instead of: Declaring a platform or C binding inside this library.
  Correction: Move the foreign declaration outside this library and supply any needed capability through its API.
  Check evidence: native_ast; package-scope foreign declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Severity: error; suppressible: true; baselineable: true
  Effective selector: `{"kind":"pattern","attribute":"","on":"","from":"","names":[],"roles":[],"except_roles":[],"match":"foreign","name":"","exported":false,"requires_param":{"index":0,"type_suffix":""},"at":"","mutable":false}`

<!-- odx:end -->
