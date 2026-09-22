# Milestone 8 release-readiness research

Research only; no implementation changed. Reviewed ROADMAP milestone 8, README,
CI/build configuration, command/schema surfaces and previous executable proofs.
Observed host: Darwin arm64; supported local Odin installation:
`dev-2026-09-nightly:a2fb372`. The existing binary was used for bounded smoke
probes; fresh final debug/optimized builds and full CI remain acceptance work.

## Release recommendation and alternatives

Recommend an **experimental source-build scope**, conditional on final validation
and the parallel external-project evaluation. The demonstrated product is a
project-policy checker with portable guidance and honest evidence boundaries.
Do not claim general production readiness, universal Odin compatibility, external
adoption success or improved agent productivity.

| Approach | Benefit | Cost and decision |
| --- | --- | --- |
| Broad stable cross-platform binary release | Easier installation and strong compatibility promise | No platform matrix, binary publication workflow or sustained external evidence establishes this scope. Defer. |
| Narrow experimental source-build distribution | Matches current reproducible workflow; enables feedback without new packaging | Users need the pinned compiler and must understand boundaries. Recommended if final checks pass. |
| Defer all availability until extended pilots | More confidence before encouraging adoption | Delays useful bounded experimentation; unnecessary if limitations and release status are explicit. Reconsider if the external pilot reveals blocking defects. |

This is a release assessment decision, not authorization or a requirement to tag,
publish artifacts, change repository visibility, or install software globally.

## Platform and distribution evidence

- `.github/workflows/ci.yml` declares one `ubuntu-latest` job invoking
  `mise run ci`. A configured workflow is not an observed successful remote run.
- The current execution environment supplies macOS arm64 evidence. Do not call it
  a Linux validation result. Windows and other host/toolchain combinations were
  not exercised in this task.
- `mise.toml` selects `odin = "dev-2026-09"`; record actual compiler revision
  `a2fb372` in the assessment because the nightly label alone is less precise.
  Native parser/doc-format layouts and compiler behavior tie compatibility to
  the selected toolchain. Existing evidence validation rejects unsupported format
  or missing compiler evidence instead of silently returning clean checks.
- macOS sanitized tests require LLVM clang under the configured Homebrew LLVM 22
  location; this is part of the observed test environment, not an odx runtime
  dependency for every user. Unix shell/install tasks are not Windows packaging.
- `mise run release` produces an optimized local `build/release/odx`; no checked-in
  workflow builds/releases a versioned platform artifact matrix. `install` copies
  that binary to `~/.local/bin`. Publishing and package-manager distribution are
  outside the evidence here.
- Built-in rule files are embedded at build time; custom project topics load
  from project files. A rebuilt binary is needed after embedded rules change.

The final record should distinguish: locally tested macOS arm64, configured but
unobserved Linux CI, untested Windows/other compiler revisions, and the exact
commands actually run. Adding CI matrix entries without executing them does not
close the missing-platform evidence.

## Commands and compatibility that must survive

| Contract | Existing proof / final check |
| --- | --- |
| `check` exit 0/1/2, warning strictness, baseline visibility | Report tests and M7 adoption probes; run again in full CI. |
| Schema 1 structured findings, repair metadata and coverage | M1/M4 probes and report tests; preserve additive fields and compatibility `blocking`, not a status decision. |
| Source all-branch scope versus compiler selected-target scope | M1/M5 probes; describe `complete` within evidence boundaries, not whole-project validity. |
| Scoped and `--since` dependency evidence | M2 graph/incremental probes; graph discovery may be wider than reporting selection. |
| Public selectors, validation, custom rule tests | M3/M6 probes; local rules must retain effective project settings. |
| Managed guidance freshness/ownership | M4/M6 probes plus checked-in root/minimal/strict freshness checks. |
| Baseline format 2 and explicit maintenance | M7 probes; checks do not write acceptance; v1 migration is explicit current-debt acceptance. |
| Read-only suppression audit | M7 adoption probes; unavailable evidence exits 2 rather than claiming a clean audit. |
| Hook behavior | Hook is report-only and exits 0; do not infer that normal CI checks cannot fail. |

No reproduced gap in these public surfaces justifies new flags, changed defaults
or another schema revision in milestone 8.

## Determinism probe and limits

Ran each command three times against both copyable policy projects with the same
existing binary, source, host and configuration:

```text
odx check --ci --json --root examples/policies/minimal
odx for --emit-md --root examples/policies/minimal
odx check --ci --json --root examples/policies/strict
odx for --emit-md --root examples/policies/strict
```

All 12 invocations exited 0. Each group's stdout/stderr were byte-identical.
Both check reports had schema 1, complete coverage and zero findings. Source
inspection confirms sorted JSON maps, sorted findings and normalized guidance
fingerprints. This establishes bounded same-input repeatability only; compiler
paths, target, environmental errors and source selections can legitimately alter
output. Do not promise byte identity across roots/hosts or compiler versions.

Final optimized-build smoke should repeat these checks with the freshly built
release binary and check all committed managed guidance. Prefer preserving a
small executable smoke proof if it meaningfully protects packaging. Avoid
re-running the full suite multiple times without changes or new failures.

## Documentation defects to correct

The README currently makes claims that contradict the corrected product:

1. “every guarantee the compiler offers is switched on” overstates doctor's
   bounded discovery/configuration checks and optional project decisions.
2. “never blocks anything” conflates a report-only hook with nonzero CLI/CI exits.
3. The lead describes fixed role names and the role paragraph enumerates
   pure/service/edge as if those were the allowed vocabulary; M6 proves arbitrary
   project role names and no-role projects.
4. Agent-loop prose says the negative productivity result was measured, then
   labels rerun failures “noise”. The small uncontrolled pilot does not establish
   either a universal negative effect or that particular failures were noise.
   Retain historical rows only as inconclusive observations, explicitly separate
   compilation/tests/compliance/turn counts, and make no causal claim.
5. “escape hatch for every reason” overlooks non-suppressible internal findings
   and project rules that disable suppression/baselining.
6. The final “Future Tests” item mandates a brace/one-line-if style unrelated to
   selected project contracts; remove or clearly relocate it as an unadopted
   idea rather than a promised capability.
7. Command synopsis says `exit 1 on violations` without warning/baseline nuance;
   align with the already accurate nearby 0/1/2 contract.
8. The README lacks a direct source-build/compatibility/release-status entry
   point. Put the actual supported scope and links early enough to discover.

These are documentation changes, not reasons to invent new enforcement or alter
existing defaults. Preserve detailed boundaries already correct later in README.

## Necessary acceptance work

After all research completes, correct README claims and record a final milestone
release assessment. The parent task must incorporate the external-project pilot's
false positives, known misses, authoring effort, latency, maintenance costs and
failures. Set usability/latency budgets before measuring the pilot, as required by
the roadmap; this research did not run a latency measurement or choose a budget
from observed times. A synthetic example is not external adoption evidence.

Run a fresh build and full repository CI once final changes are in place; run an
optimized build and basic copied-policy/schema/guidance smoke. Record compiler,
host, commands, results, unavailable platforms and any observed failures. The
assessment should choose experimental scope, more iteration, reduced scope or
deferral from the evidence. No agent productivity experiment is necessary unless
making an agent productivity claim, which is not recommended here.

Remaining limits: no release artifact distribution test, no new external-user
interview, no live agent trial, no current remote-CI outcome, and no other-host
execution in this research. The release decision must keep these visible rather
than convert configured or synthetic capabilities into stronger guarantees.
