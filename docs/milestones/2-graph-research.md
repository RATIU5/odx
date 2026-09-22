# Milestone 2: source graph research

Research date: 2026-09-21. Reference toolchain:
`/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09`.
This records the implementation immediately after milestone 1, before milestone 2 changes.

## Reproductions

Run `build/odx check --root tests/fixtures/contract --fast --topic dependencies`.
The full scan exits 1 and reports `dependencies/R2` on
`dependencies_r2_via/fires.odin:4`: the pure package reaches `core:os` through
`dependencies_r2_svc`. Adding `dependencies_r2_via/fires.odin` or its containing
directory to the command removes that finding. Milestone 1 makes the scoped scan
exit 2 with unsupported graph evidence, rather than its older false-clean result.
File, directory, `--since`, and successful hook checks all ultimately use
`make_ctx` with selected paths, which loads only those packages.

An independent two-package project reproduced an additional false negative:

```json5
{
  version: 1,
  roles: {pure: ["app"]},
  dependencies: {pure: {may_import: ["local:*"], deny: ["core:os"]}},
  odin: {collections: {local: "."}, explicit_allocators: "off"},
}
```

`app/app.odin` imports `local:helper`; `helper/helper.odin` imports `core:os`.
Both contain ordinary package declarations. Full fast dependency checking exits
0 with complete R2 evidence. `import_target` returns the correct helper directory
but no role; `reach_denied` and coverage mistakenly classify that as external.
Adding `exclude: ["helper/**"]` also exits 0 with complete R2 evidence. Exclusion
silently removes required knowledge instead of identifying a boundary.

A second probe assigns `helper` the service role, lets pure import service, and
imports `../alias`, where `alias` is a symlink to `helper`. The checker reports
`pure package may not import alias` instead of resolving the service role and
reporting the transitive `core:os` reach. Discovery appropriately avoids walking
symlink directories, but edge resolution needs canonical identity.

## Recommended model

Parse every discovered project package once into graph evidence. Keep selected
reporting packages separate, referring to the already parsed data. Emit ordinary
rule diagnostics only for selected packages; reachable failed parses still make
their architecture evidence incomplete. An unrelated malformed package must not
invalidate every selected package's architecture result.

Classify each edge independently of roles:

- Project package: canonical path resolves to a discovered package, including
  packages without roles and configured collection paths inside the root.
- Explicit opaque toolchain leaf: an unshadowed `core:`, `base:`, or `vendor:`
  import. Its literal collection path remains available for policy matching.
- Unavailable evidence: missing/excluded project package, unknown collection,
  configured collection outside the project, or relative import outside the
  project. Required traversal must not silently treat these as clean leaves.

Resolve configured collections before recognizing builtin collection names.
Use `canonical` on resolved filesystem paths and honor the boolean result of
`rel_of`; do not infer locality from a nonempty role. Normalize package identity
without changing the original import spelling used for direct policy and stable
finding subjects. The installed `core:strconv.unquote_string` decodes escaped
and raw string literals and returns an explicit success value; trimming double
quotes alone is insufficient.

Define `may_import` as direct role/import-pattern permission. Define `deny` as
matching direct imports and imports reachable through project package edges,
with opaque toolchain leaves disclosed as the terminal boundary. This is not a
proof that code has no runtime effects. Source edges cover inactive/platform
files consistently with milestone 1. A recursive native AST visitor can collect
imports and foreign declarations inside conditional source, avoiding a second
ad hoc file-level interpretation. Compiler rejection of some placements belongs
to compiler evidence and does not make a source branch disappear.

Preserve the existing distinction between a selected package's test imports
(checked, with existing test allow exceptions) and dependency test files
(excluded from transitive production reach). Test-only dependency imports must
not contaminate every importer. Foreign imports and foreign blocks require
separate handling; a foreign block can exist without a foreign import. Never
claim transitive foreign freedom through an opaque external package.

Build adjacency in sorted package/file/source order. Visit each canonical node
once per reachability query, tolerate cycles, and choose the first reproducible
chain. Sort denied destinations before reporting them; map iteration is not a
stable witness policy. Deterministic depth-first chains suffice; shortest paths
would add complexity without a requirement.

## Alternatives and acceptance probes

Complete graph loading is the simplest reference implementation: source parsing
cost increases for scoped checks, but there is one resolution model and no
invalidation state. Dependency closure can reduce parsing but requires loading
on demand, cycle handling, exclusion failures, and reverse-impact work for
incremental checks. Persisted graphs add toolchain/configuration/deletion
invalidation and are not justified before measuring the uncached implementation.
Compiler graphs are useful target-specific evidence, but cannot replace the
source-wide graph while preserving inactive/test source coverage.

Acceptance should compare the selected package's R2 findings under full, file,
directory, since, and hook reporting. Add positive and negative cases for
unassigned collection packages, canonical aliases, cycles, denied alternatives
with deterministic witnesses, excluded/missing dependencies, malformed reached
versus unrelated packages, test-only edges, and inactive source. Preserve
existing direct finding subjects to avoid needless baseline churn. Measure full
and scoped scans after implementation; this research alone does not establish
their final performance.
