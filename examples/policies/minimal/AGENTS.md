<!-- odx:begin v1 -->
## odx

Policy fingerprint (generation 5): `7e2a22bb66165c18dadde5834660664910908638a4dec0e2d12dcff8227b1cf8`

Scope: all discovered project packages. Rules below are the union applicable to this selection; each rule retains its own scope.
- Package `parser`: role `(unmapped)`

Run `odx check --json` for findings and coverage. Exit 0 alone does not establish complete analysis. Use `odx policy --verify <file>` to check freshness or `odx policy --write <file>` to regenerate; repeat the selected package path.

- **library/R1** [error] Declare no mutable package-scope values, including inactive when branches and foreign blocks.
  Scope: all roles, including unmapped packages
  Why: Callers own parsing state and can use independent instances of this library.
  Correction: Move the variable into a caller-owned struct or procedure-local value.
  Evidence: native_ast; package-scope decl declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Effective selector: `{"at":"package_scope","kind":"pattern","match":"decl","mutable":true}`

- **library/R2** [error] Declare no direct foreign imports or foreign blocks, including inactive when branches.
  Scope: all roles, including unmapped packages
  Why: The parsing library keeps its own source independent of foreign bindings.
  Correction: Move the foreign declaration outside this library and supply any needed capability through its API.
  Evidence: native_ast; package-scope foreign declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof
  Effective selector: `{"kind":"pattern","match":"foreign"}`

<!-- odx:end -->
