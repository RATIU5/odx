<!-- odx:begin v1 -->
## odx

Policy fingerprint (generation 5): `2104855ea624b2d05f5a32140445944e976a89de3cc4c33b819408c03e0055e3`

Scope: all discovered project packages. Rules below are the union applicable to this selection; each rule retains its own scope.
- Package `odx`: role `edge`

Run `odx check --json` for findings and coverage. Exit 0 alone does not establish complete analysis. Use `odx policy --verify <file>` to check freshness or `odx policy --write <file>` to regenerate; repeat the selected package path.

- **dependencies/R2** [error] Ordinary imports obey the role's may_import and deny policy; deny also follows imports through included project production source, stopping at built-in collection boundaries.
  Scope: all roles, including unmapped packages; requires a dependencies policy for the package role
  Why: The compiler checks import validity; a project chooses allowed dependencies. Source import boundaries do not prove foreign-access freedom or runtime purity.
  Correction: Remove or restructure the reported import chain so direct imports satisfy may_import and no included dependency reaches a denied import under this role's policy.
  Evidence: source_import_graph; recursive ordinary source imports with direct test allow exceptions; dependency *_test.odin edges omitted; unconfigured core/base/vendor collections are opaque leaves; required missing/excluded/unknown/outside project evidence is unavailable; no foreign or runtime effect guarantee
  Effective selector: `{"from":"dependencies.may_import","kind":"banned_import"}`

- **errors/R3** [error] Exported non-test procedures whose named final result matches the configured error classification carry @(require_results).
  Scope: all roles, including unmapped packages
  Why: This project requires explicit result acknowledgement for selected APIs. The compiler rejects bare calls to attributed procedures but permits assigning any or all results to `_`.
  Correction: Add @(require_results) to the reported procedure declaration; callers must acknowledge its results, including by explicit discard.
  Evidence: compiler_entities; compiler-selected exported procedure declarations, excluding @(test); canonical named final-result suffixes and optional structural classification from errors configuration; attribute presence only, no error-intent or caller-handling proof
  Effective selector: `{"attribute":"require_results","kind":"require_attribute","on":"exported_procs"}`

### errors: reviewer advice (not mechanically enforced)
Roles: pure, service, edge

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
