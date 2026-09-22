# Milestone 8 real-source pilot research and preregistration

Preregistered at **2026-09-22 04:49:54 UTC**, before running odx outcome or
latency measurements for this milestone. This is an execution plan, not results.
Research may inspect source and configuration; measurements begin only after all
milestone research finishes and implementation is assigned.

## Sources and scope

The primary repeatable input is the supported Odin installation's
`examples/demo/demo.odin`, from toolchain `dev-2026-09:a2fb372b7`. The installed
`examples/README.md` describes demo as a language-basics example and `examples/all`
as an all-core/vendor import harness. Demo is real externally authored source
beyond odx, but educational code is not evidence of application adoption. Record
the exact file SHA256, byte/line count, compiler version, host OS/architecture,
and odx revision before measurements. Read source from the installed toolchain and
copy it to a temporary pilot root; do not modify the installation or vendor a
new upstream snapshot into this repository.

A local external application's clean tracked snapshot is available as an
optional broader pilot: 40 Odin source files in four source packages, with a
different compiler pin and native graphics dependencies. Use only a temporary
copy of tracked source and needed existing dependencies. Record aggregate counts
and outcomes, avoid publishing application source or unrelated private details,
and do not modify the original project. Treat unavailable native dependencies or
toolchain mismatch as a failed/incomplete compiler-evidence result, never clean
compliance. This optional sample is not a reproducible public-release requirement.

The second selected public input is `core/container/queue/queue.odin` from the
same installation. Read-only inspection shows a maintained dynamic double-ended
queue with only `base:builtin` and `base:runtime` imports, generic procedures,
and allocator-error return types. Copy it to an ordinary temporary package as a
real library counterweight to demo. This selection is fixed before measurements;
compilation feasibility remains unmeasured. Apply both policies to both inputs.

Avoid `examples/all`: its purpose is importing the compiler distribution, so its
runtime and platform failures would mainly measure that harness. Any input
substitution must be documented before measuring outcomes.

## Competing approaches

1. **Only copied odx policy examples.** Repeatable and cheap, but already covered
   by milestone 6 and incapable of establishing behavior on external code.
2. **Pinned official source under temporary project-owned policies.** Repeatable
   on the supported installation, avoids network drift and hidden application
   dependencies, and permits exact source references and review. Educational
   source is intentionally broad and may resist strict policies; that is useful
   negative evidence, not a defect in the source.
3. **A local real application.** Better source-size, package-boundary, foreign
   code, and maintenance diversity; less publicly reproducible and more likely
   to involve compiler/dependency mismatch. Useful supplementary evidence with
   clearly limited portability.

Select approach 2 as primary, optionally supplement with 3. Neither gives
external maintainer endorsement or establishes an AI-productivity benefit.

## Policy experiences to measure

Create two temporary policy projects over identical unmodified external source.
Select policies before outcome measurements; do not tune away findings to obtain
a passing result.

**Minimal:** two local native-source restrictions with no architectural roles:
no mutable package-level declarations and no direct foreign import/block syntax.
These reuse milestone 6's precise project-owned checks. Disable unrelated
built-in error conventions, explicit-allocator requirements, and file-tag audit.
The experiment asks whether these two restrictions remain isolated, produce
actionable findings, and avoid unrelated policy leakage on real source. A
language-demo author has not endorsed this style.

**Strict:** use the five existing milestone-6 local rule files without adding
selectors: the three dependencies rules, allocator R1, and errors R3. Copy each
real input into `domain/`, map only that package to role `domain`, and use the
existing domain dependency policy with `may_import: ["domain", "core:*"]` and
`deny: ["core:os", "core:os/*", "core:net", "core:net/*", "core:sys/*"]`.
Set `errors: {types: ["Error"], structural: false}` to classify only named Error
suffixes, and retain the strict example's Odin configuration (empty extra flag
lists, explicit allocator tags for all files, supported compiler version, default
file-tag audit). Exclude `.odx/**`, `cases/**`, and `build/**`; no other packages
or roles are introduced. The minimal policy's source restrictions correspond to
the strict policy's existing declaration/foreign checks; additional strict
findings are role import boundaries, allocator directives, error result
acknowledgement, or file-tag audit. A one-package sample establishes direct
import behavior only; inter-package architecture remains a synthetic-suite proof.
Intentional file directives and valid rejected language constructs are policy
adoption costs, not upstream defects. Retain exact effective configuration and
local-rule files as artifacts. No speculative panic/os.exit rule is added.

Run generated guidance write/check for each selected policy and inspect its scope
against enabled rules. If initial real code violates policy, use the explicit
baseline lifecycle to measure gradual adoption instead of rewriting upstream
source wholesale. Include one temporary source edit demonstrating the documented
whole-file baseline invalidation cost; restore the original snapshot afterward.

## Budgets registered before results

These targets describe an interactive local policy workflow on the selected
small inputs; they are not general release SLAs.

| Measure | Budget and reason |
| --- | --- |
| Policy setup | At most 15 minutes elapsed authoring per policy after source copying; two/few-rule adoption should fit a short setup session. Record start/end, files and nonblank configuration/rule lines, failed attempts, and manual decisions. |
| Fast check latency | Median at most 2 seconds per sample with fewer than 50 source files; useful for local edit feedback. |
| Complete check latency | Median at most 10 seconds per such sample; acceptable as an explicit pre-commit check including compiler processes. |
| Timing protocol | One recorded cold run, one warm-up, then five measured runs per mode/policy; report all values and median, same source and configuration, sequential execution, no concurrent build/test jobs. |
| Finding review | Review every distinct rule/location outcome up to 30 findings per policy; above that report total and deterministic first 30 with the unreviewed remainder clearly marked. No unreviewed result supports a no-false-positive claim. |
| Correctness gate | Zero demonstrated false positives relative to the stated syntactic contract; any failure narrows the release claim or requires repair and rerun. A legitimate Odin construct forbidden by the chosen policy is an adoption cost, not automatically a matcher false positive. |
| Actionability | For every reviewed finding, verify rule/location, actual triggering source, correction that changes the specified construct, and bounded evidence wording. Count unhelpful/misleading items separately. |
| Maintenance | One configured-policy change must stale generated guidance; one ordinary source edit must show baseline consequences without an ordinary check rewriting files. Record required commands and debt reopened. |

Budgets may fail. Do not redefine them after results; explain failures and choose
release narrowing, further iteration, or deferral accordingly. Record automated
elapsed setup separately from human authoring effort: an agent's wall clock and
configuration-line count do not establish a new user's learning cost.

## Counterexamples and validation protocol

Separate three sources of evidence:

- Unmodified real code: audit genuine findings and legitimate rejected style.
- Mutations of a temporary copy: introduce one clearly violating declaration,
  one repeated forbidden call in a different function, and a comment/string
  spelling the same syntax; establish detection and absence of textual false
  positives. Compile mutations when their validity matters.
- Existing synthetic contract suites: preserve full/scoped architecture,
  malformed-evidence, public-selector, suppression, baseline, and guidance
  guarantees without pretending those are real-project adoption results.

Known misses to demonstrate or explicitly retain: called wrappers and aliases
outside syntactic call spelling, effects through ordinary imports, legitimate
code sharing a prohibited spelling, no semantic allocation/purity claim, and
conditional/platform source scans differing from active compiler configuration.
For every invocation retain exit status, coverage status/reasons, JSON findings,
source fingerprint, effective policy, command, and timing. Compiler failure
prevents complete-check certification; `--fast` success remains partial evidence.

Do not execute application runtime/UI code or source examples merely to obtain
lint results. Compiler checks establish validity under the selected target only;
they do not measure application behavior. Do not run an agent-productivity
experiment: milestone 8 permits a deterministic policy release decision with
that question explicitly unclaimed.

## Research handoff

No new matcher, cache, preset system, parser backend, or product behavior is
justified by this preregistration. Implement a repeatable pilot harness and
artifact/reporting path after research approval, measure honestly, then base the
release decision on actual failures and costs. Revisit the source selection if
the installed pin cannot be identified or copied reproducibly, or if native
dependencies prevent evaluating the optional application; retain the failed
attempt in the final record.


## Execution pin clarification before first measured run

Read-only verification before the 04:56:07 UTC measurement start established that
this machine's mise compiler reports `dev-2026-09-nightly:a2fb372`, while its
Homebrew compiler reports `dev-2026-09:a2fb372b7`. The pilot executes the exact
mise compiler and reads its `odin root`; it does not mix the Homebrew executable
with mise sources. The retained harness requires the September pin and revision
prefix and exact source hashes:

- demo: `716c752d843c434bd626f6703fa9c8a791a4090f26b2efe3a0cac3333e4afef4`
- queue: `f1809a37d6b4ec1f9d383a2fc357a7bbf4d666b2ac4eb109d065f6279dc53ab6`

The copied strict error rule's metadata/examples are adapted from the example's
Domain_Failure/Storage_Failure names to the preregistered Error suffix. Its
selector is unchanged; the original repository example is untouched. This
metadata maintenance is part of authoring cost, not hidden policy tuning.
