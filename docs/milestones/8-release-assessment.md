# Milestone 8: usefulness and release scope

**Decision: retain experimental source-build scope on macOS arm64 with the pinned
Odin toolchain. Defer stable, production and cross-platform release claims.**
The real-source pilots and final checks below complete milestone 8 with that
reduced release scope. This decision does not publish a tag or binary artifact.

The evaluated workflows provide bounded policy findings and matching instructions.
Their value depends on whether the chosen restrictions fit the project. odx does
not require a model, and this assessment makes no
agent-productivity claim. Existing policies remain optional project choices;
Odin conventions are not universal requirements merely because odx can check them.

Research source baseline: `4310268` (milestone 7 committed during research).
The assessed compiler is the mise-managed nightly revision listed below; results from
other installed compilers must be identified separately.

Research completed before implementation:
[real-source protocol and budgets](8-pilot-research.md),
[release readiness](8-release-research.md),
[alternatives and historical agent evidence](8-alternatives-research.md).
The real-code evaluations are recorded separately in
[library pilot results](8-pilot-results.md) and
[application results](8-application-results.md).

## Alternatives and decision

| Approach | Benefit | Cost and decision |
| --- | --- | --- |
| Stable cross-platform binary release | Simple installation with a strong compatibility promise | Current platform and external-adoption evidence is insufficient. Deferred. |
| Experimental source build on the assessed host/toolchain | Exposes bounded utility with a reproducible development workflow | Users must manage the pinned compiler and review policy limits. Selected scope. |
| Defer all availability for extended pilots | More adoption evidence before encouraging use | Unnecessary if focused evaluations and correctness checks pass; revisit if they expose blocking gaps. |

Keep native Odin parsing, project graph evidence and selected compiler evidence.
Compiler checks and odinfmt remain complementary tools. The alternatives review
compares the actual policy requirements; it does not equate superficially similar
checks or treat published capabilities as independent correctness proofs. No
preset framework, second parser, new built-in rule or caching layer is justified
by release preparation alone.

## Enforced facts and limits

| Evidence or feature | Supported claim | Boundary |
| --- | --- | --- |
| Native source/AST selectors | Selected declarations and call spellings match a documented syntax predicate | Includes inactive collected branches; does not resolve arbitrary identities or prove runtime behavior. |
| Variable declarations | `mutable: true` follows the AST's declaration flag | Includes `@(rodata)`; it does not establish writable storage or harmful shared state. |
| Source import graph | Ordinary imports satisfy configured direct and transitive boundaries within included project evidence | External collection leaves and missing/excluded evidence have documented limits; no foreign-access or purity proof. |
| Compiler diagnostics/entities | Selected build configuration supplies checked diagnostics and exported facts | Compiler-target scope differs from all-source policy scope; tests are not executed by `check`. |
| Error classification | Configured named-result suffixes and optional structural heuristic select attribute requirements | Status/optional results can match; attributes acknowledge results, including explicit discard. |
| Allocator policy | Selected files carry the explicit-allocator vet directive | No allocator-flow, ownership, allocation-freedom or lifetime proof. |
| Reviewer advice | Generated prose expresses project review questions | Its truth and compliance are not mechanically established. |
| Guidance freshness | The managed section matches current policy and selected package scope | Fresh instructions do not establish source compliance or agent obedience. |
| Baseline format 2 | Accepted occurrences bind to unchanged source-file snapshots | Edits reopen acceptance; policy/dependency historical meaning is not captured by source identity. |

## Compatibility and platform matrix

| Surface | Assessed scope | Status |
| --- | --- | --- |
| Host execution | macOS arm64, Darwin 27.2.0 | Fresh CI, real-source pilots and optimized smoke passed. |
| Compiler | Odin `dev-2026-09-nightly:a2fb372` | Pinned assessed revision; other revisions unverified. |
| Linux | `ubuntu-latest` CI workflow exists | Current remote execution outcome not verified in this assessment. |
| Windows and other architectures | No execution evidence in this task | Unverified; Unix shell/install tasks are not a Windows distribution. |
| Distribution | Source checkout, debug build and local optimized binary | No platform artifact publication, signing or package-manager delivery tested. |
| Sanitized macOS tests | Homebrew clang 22.1.8 at the configured LLVM 22 path | Address sanitizer and bad-memory tracking passed. |

Built-in policies are embedded; changing them requires rebuilding the binary.
Project topics load from local files. The compiler must be available for checks
requiring compiler evidence; missing or unsupported evidence cannot certify
compliance. Toolchain version drift and doc-format incompatibility remain explicit
compatibility constraints.

## Command and deterministic-output contracts

| Contract | Preserved behavior | Acceptance evidence |
| --- | --- | --- |
| `check` | Exit 0: no failing unaccepted findings; 1: failing findings; 2: tool/config error. `--strict` fails warnings. | M7 adoption/report tests and optimized smoke passed. |
| Schema-1 JSON | Findings, repair metadata, coverage and aggregate counts remain available; `blocking` is compatibility metadata. | M1/M4/M7 probes and optimized smoke passed. |
| Coverage | Fast/scoped/empty selections disclose boundaries; complete evidence is not synonymous with no findings. | M1/M2 and real-source probes passed. |
| Local rule authoring | Strict selector validation and project-config-aware rule examples | M3/M6 probes passed. |
| Guidance | Managed ownership, explicit writes, scope-sensitive freshness | M4/M6 probes, real-source drift and all committed guidance checks passed. |
| Adoption | Read-only checks; explicit baseline add/prune/regen; suppression audit reports unavailable evidence | M7 and real-source maintenance probes passed. |
| Optional edit hook | Reports and exits 0 | Distinct from CLI/CI failure behavior. |

The readiness probe ran full JSON checks and emitted guidance three times for
each minimal/strict example: all 12 invocations exited 0, checks reported complete
evidence with zero findings, and each group produced byte-identical output.
This is same-host/same-input evidence, not a cross-root or cross-toolchain byte
identity promise. Final fresh optimized-binary smoke results belong below.

## Real-project evaluation results

Before measurement, the protocol selected a 2-second fast-check median and a
10-second full-check median for inputs below 50 source files, plus a 15-minute
policy-setup budget. Each timing series retained its first invocation, a warm-up,
and five measured runs. The detailed records retain every observation and exact
source fingerprints; timings were serialized outside CI.

| Real source | Findings, minimal / strict | Full median seconds, minimal / strict | Evidence and cost |
| --- | --- | --- | --- |
| Odin demo, pinned `a2fb372`, 2,626 lines | 3 / 8 | 0.101 / 0.188 | Includes a Windows-only foreign import in the all-source scan and intentional directive-policy conflicts. |
| Odin queue library, same pin, 469 lines | 0 / 7 | 0.037 / 0.068 | Caller-owned fields satisfy the minimal rule; strict adds a tag and six result-attribute requirements. |
| Plastella, tracked `78961ae1cce507b9673d98eba908c656eb92f4b3`, 41 files / 7,021 lines | 22 / 84 | 0.545 / 0.700 | Deliberately imposed policies expose GUI dependency, vendored FFI and declaration-policy friction. |

All measured latency budgets passed; fast medians ranged from 0.009 to 0.041
seconds. Public source is reproducible through `mise run validation`; the local
application is supplementary and requires its original private snapshot. These
are policy overlays on existing code, not endorsements or external-user adoption.
The application pins a July compiler, but September checks completed without an
observed incompatibility. No application runtime, linker or application tests
were exercised.

All 18 public finding rows, all 22 application minimal findings and the first
30 of 84 application strict findings were reviewed. No mismatch with the exact
syntax/graph predicate was found in those reviewed samples after the diagnostic
fix below. The remaining 54 strict findings are unreviewed. Ten minimal
application declaration findings and three reviewed strict declaration findings
carry `@(rodata)`: calling these harmful mutable state would overstate the
evidence, and the generic move-state repair is less useful for those tables.
This is material policy-fit and wording friction, not a broad zero-false-positive
claim. Strict application adoption would require design work not estimated here.

The public harness demonstrates one actual repair: adding `@(require_results)`
to queue's `init` compiles and removes its finding; reverting restores it.
Comment-only source edits reopen 3, 5, 0 and 7 accepted baseline entries across
demo minimal/strict and queue minimal/strict respectively. Checks preserve the
baseline bytes. Valid policy edits stale guidance. Those are observed utility
and maintenance costs, not proof of cheap adoption.

Copying/adapting existing policies took an agent a few minutes, but neither pilot
isolated first-time authoring effort. The 15-minute authoring budget is **not
established**. This unmet usability evidence and the small source sample are
reasons to retain experimental scope rather than claim broad readiness. No
threshold was relaxed after observing results.

## Pilot-driven corrections and compatibility

The initial queue scan emitted nine error-rule rows for six declarations.
Compiler scope entries for aliases referenced the same entity repeatedly. The
checker now processes each compiler entity once per package and still applies
each independent rule. A regression using chained aliases, distinct procedures
on the same line, attributed procedures and two rules failed six assertions on
the old binary and passes on the correction. The final queue result has six
error findings plus one allocator-tag finding.

Existing baselines containing the redundant rows may now have stale surplus
entries. Use explicit `baseline prune` after complete analysis; checks still
never rewrite the ledger. This changes diagnostic multiplicity, not the rule's
selection or schema. The second correction removes the empty role suffix from
foreign diagnostics in roleless projects. Final application checks preserved all
finding identities and corrected all seven such messages. The README now makes
the `rodata` boundary, optional policy scope and inconclusive agent pilot explicit.

## Final validation

Validated the working tree based on `4310268` plus these milestone changes, on
Odin `dev-2026-09-nightly:a2fb372`, Darwin 27.2.0 arm64. macOS tests used Homebrew
clang 22.1.8 through the configured LLVM 22 path.

- Fresh debug build with the repository's vet, strict-style and warnings-as-errors flags passed.
- `mise run validation` passed 306 assertions. The pilot record retains its binary
  hash, source hashes, full command outputs and measured values.
- `mise run --force ci` passed: 37 sanitized/memory-tracked unit tests; 49 evidence,
  113 architecture, 121 contract, 105 guidance, 72 error-semantics, 45 allocator,
  164 independent-policy, 190 baseline and 46 suppression/adoption assertions;
  plus fixtures, exemplars, compiler redundancy audit and init-preservation smoke.
- Self-check completed across 57 files and 13 packages with no findings. Doctor
  reported zero errors and two existing warnings: absent optional hook setup and
  allocator advice scoped to unused roles.
- `mise run --force release` built the optimized binary. Both example policies
  produced complete clean schema-1 reports and identical outputs across three
  repeated checks and guidance emissions. Root/minimal/strict guidance was current.
  A temporary new declaration failed with exit 1; fast checking disclosed partial
  evidence; a missing compiler failed with exit 2 and incomplete evidence.
- `git diff --check` passed.

Initial pilot execution exposed the duplicate/message defects and an invalid
test-only guidance mutation. The first final-task attempt also found an unused
field left in a probe initializer; removing it allowed the 306-assertion run.
These failed attempts are retained in the pilot record. Full CI and optimized
smoke passed on their first final runs. No platform publication, remote Linux
run, Windows execution or independent-user trial is claimed.

## Historical agent pilot and future evidence

An earlier ten-task, fixed-order pilot compared no odx, prompt guidance and a
Stop-hook condition. Initial compile/test outcomes were lower in the odx
conditions; selective reruns passed everywhere. The retained harness did not pin
a model, and stopping/scoring were coupled. These observations do not establish
productivity benefit, harm, or the cause of individual failures. No new agent
experiment is needed for the deterministic-policy release decision.

Reconsider broader release after representative external users validate authoring
and adoption cost, supported host/toolchain combinations execute the full suite,
and distribution requirements are tested. Reconsider agent-productivity claims
only with prespecified independent outcomes, resource budgets, pinned tools/models,
balanced or randomized order, repeated complete trials and retained failures.
