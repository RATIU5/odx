# Milestone 8 public real-source pilot

The preregistered inputs were the supported Odin distribution's language demo
and maintained queue library, each checked under minimal and strict local
policies. These are externally authored source, not external maintainer adoption
or endorsement. The separate optional application pilot broadens that evidence;
this document covers only publicly reproducible inputs.

## Reproduction and artifacts

Run `mise run validation` after building current odx. The harness requires
`ODX_ODIN` to identify the supported compiler. Its default binary is `build/odx`
(`ODX_PILOT_BIN` overrides it), and its default output directory is
`build/milestone8` (`ODX_PILOT_OUT` overrides it). Each invocation retains a new
`run-*` directory and updates `latest-summary.json`. Generated artifacts include
the copied source, exact local policies/configuration, generated guidance, every
command's stdout/stderr/exit/duration, source and binary hashes, host and revision,
and all individual timing observations. Nothing modifies the compiler
installation or upstream source. Generated source copies stay outside version
control.

The compiler used here is the mise installation reporting
`dev-2026-09-nightly:a2fb372`. The Homebrew executable reports a different version
spelling; the harness reads the root of the executable it actually invokes.
Exact input hashes are enforced before measurement:

| Input | Lines | SHA256 |
| --- | ---: | --- |
| `examples/demo/demo.odin` | 2,626 | `716c752d843c434bd626f6703fa9c8a791a4090f26b2efe3a0cac3333e4afef4` |
| `core/container/queue/queue.odin` | 469 | `f1809a37d6b4ec1f9d383a2fc357a7bbf4d666b2ac4eb109d065f6279dc53ab6` |

Each project contains one unchanged source file in `domain/`. Minimal selects
only mutable package declarations and direct foreign declarations. Strict reuses
the milestone-6 five local rules, maps the sample to domain, uses its domain
import restrictions, and requires allocator directives and Error-suffix result
acknowledgement. Structural error inference is off. The copied error statement,
topic summary, and example type names are updated consistently with that suffix;
the selector is unchanged. See the preregistration for exact configuration.

## Findings and review

Every distinct reported rule/location in these small inputs was inspected against
the upstream source; no sampling cap was reached. The following are deliberate
project-policy rejections of valid Odin, not claims that the official code is
incorrect.

- Demo's mutable `prefix_table` and `print_mutex` declarations trigger the minimal
  declaration restriction and its strict equivalent. Queue keeps mutable data
  in caller-owned queue fields and has no matching package declaration.
- Demo's direct `kernel32` foreign import appears in an inactive Windows branch.
  The native source rule finds it on macOS while the selected compiler target
  accepts the source. This demonstrates the documented all-parsed-source
  boundary; it does not demonstrate active Windows compiler analysis.
- Strict demo additionally lacks an explicit-allocator file directive, directly
  imports `core:os`, disables two vet checks, and enables language features
  without the reason required by the selected tag audit. Those directives are
  intentional educational choices; enforcing this strict policy would impose
  real adaptation cost.
- Strict queue lacks the allocator directive and the selected result attribute
  on six procedures returning `Allocator_Error`: `init`, `reserve`, `push_back`,
  `push_front`, `push_back_elems`, and `_grow`. A leading underscore does not
  constitute Odin's explicit private attribute, so the last is within the
  selected exported-procedure convention.

Initial queue output repeated `push_back` three times and `push_back_elems` twice
because compiler aliases shared their declaration position. This inflated nine
error-rule rows from six declarations. The pilot therefore revealed a real
diagnostic redundancy, which required a bounded production fix and regression
test before final acceptance. Initial demo output also exposed empty-role wording
in the foreign diagnostic. Both initial observations are retained rather than
presented as passing first-attempt evidence.

Corrective guidance identifies the source construct and an applicable change.
The retained harness adds `@(require_results)` to the actual queue `init`
declaration: complete compiler evidence remained available and its finding
disappeared. Removing that edit restored the original finding set. This does not establish compatibility for upstream callers: result
acknowledgement is an intentional API-contract change. Other reviewed corrections
are moving a package variable into caller-owned
state, moving a direct foreign binding outside the restricted package, changing
the direct import, or explicitly changing the project's directive policy. They
have not all been implemented as upstream refactorings.

No false positive was demonstrated relative to these syntactic contracts.
That limited observation is not a recall or population-wide precision estimate.
Queue remains allocation-capable and mutable through passed state despite the
minimal clean result. Ordinary imports may execute foreign code. Name suffixes
cannot establish semantic error intent, and attributes permit explicit result
discard. These are retained limits, not newly claimed guarantees.

## Authoring, latency, and maintenance costs

Budgets were registered before measurements: median fast at most 2 seconds,
complete at most 10 seconds, one first invocation and one warm-up followed by
five measured invocations per policy/mode, and at most 15 minutes policy setup
per policy. Timing excludes artifact serialization and includes child compiler
processes. “Cold” in artifact names means the first invocation of that mode; OS
page caches were not flushed. No concurrent repository build or test job ran
during the measured window.

The agent's implementation/setup interval began at 04:52:44 UTC; the first
measured run began at 04:56:07 UTC. That 3 minute 23 second interval includes
harness construction and policy adaptation, not an isolated authoring study.
Automated copy/configuration setup is measured separately in milliseconds. The
minimal policy's copied configuration, rule prose, and examples contain 61
nonblank lines; strict contains 149. Most are copied material, not newly authored
code. The only strict metadata adaptation was reconciling the selected Error
suffix with the existing example's descriptions and examples.

The 15-minute independent-user authoring budget is **not established**: there
was no new-user participant or isolated per-policy authoring timer. Agent setup
speed and copy latency cannot prove that usability claim. The first harness also
used an invalid default role for a freshness mutation; configuration validation
correctly rejected it. The corrected test changes a valid exclusion setting. The first actual mise
task attempt also caught a stale, unused `Probe.compiler` initializer after
harness cleanup; removing it allowed the final 306-assertion run to pass.

The baseline experiment explicitly accepts eligible findings, then appends a
comment to the source snapshot. All accepted findings in that file reopen;
ordinary checks preserve baseline bytes and report stale acceptance. Demo's
internal file-audit findings remain ineligible for baseline acceptance. This is
the conservative milestone-7 identity tradeoff in real source: small edits may
require broad re-review, even with no changed policy violations. Guidance
freshness detects the valid policy change and returns current when it is restored.

The negative/control mutations add one mutable declaration and separately add
comment/string lookalikes to copies of both public inputs. Complete compiler
checks establish their validity; only the actual declaration adds a source
finding. No application/example runtime code is executed.

## Acceptance record

The actual `mise run validation` execution passed **306 assertions, zero
failures**, against fresh binary SHA256
`9e72e1ccee922108ce6e13f6fc0e6dfb135d7b46fb6a483dcf75323a02af5a3f` on
Darwin 27.2.0 arm64. The working tree was based on revision
`43102688234d5dacb12acf2b567728087cae655f`; the measured binary includes the
milestone's uncommitted fixes, so HEAD alone does not identify its complete
source. Artifacts are in `build/milestone8/run-9135160104`; the
`summary.json` in that generated directory contains full-precision observations.
These ignored build artifacts are not distributed; rerunning creates a new
`run-*` directory and updates `build/milestone8/latest-summary.json`. There are 94 recorded child invocations, all with
empty stderr. Source hashes match the originals after all temporary mutations.

| Input and policy | Full policy errors | Full evidence | Fast evidence | Automated setup | Copied nonblank policy lines |
| --- | ---: | --- | --- | ---: | ---: |
| Demo minimal | 3 | Complete | Explicitly partial | 6.166 ms | 61 |
| Demo strict | 8 | Complete | Explicitly partial | 8.237 ms | 149 |
| Queue minimal | 0 | Complete | Explicitly partial | 6.330 ms | 61 |
| Queue strict | 7 | Complete | Explicitly partial | 8.107 ms | 149 |

All 18 final finding rows across the four policy/input combinations were
reviewed; zero remain unreviewed. Every measured run had the expected policy exit
and coverage, no tool error, and byte-identical complete JSON within its mode.
Package-scoped checks had complete evidence and identical complete finding
objects to their full-project counterparts. The new init attribute removed its
finding, reduced strict queue findings from seven to six, and preserved complete
compiler evidence; restoring the source restored the original set.

All timing values below are milliseconds. The registered limits are 2,000 ms
fast and 10,000 ms complete; every median met its limit.

| Input / policy / mode | First | Warm-up | Five measured observations | Median |
| --- | ---: | ---: | --- | ---: |
| demo / minimal / full | 212.042 | 104.287 | 101.438, 99.373, 107.186, 102.742, 100.287 | 101.438 |
| demo / minimal / fast | 16.676 | 16.029 | 16.296, 15.904, 16.756, 16.372, 15.966 | 16.296 |
| demo / strict / full | 190.902 | 191.104 | 190.114, 187.696, 185.850, 186.263, 192.770 | 187.696 |
| demo / strict / fast | 17.841 | 16.866 | 16.922, 16.648, 16.573, 16.889, 16.717 | 16.717 |
| queue / minimal / full | 37.417 | 38.037 | 36.738, 37.262, 36.209, 36.720, 37.599 | 36.738 |
| queue / minimal / fast | 10.357 | 9.072 | 9.008, 8.964, 8.954, 8.723, 8.732 | 8.954 |
| queue / strict / full | 67.739 | 67.293 | 68.256, 68.793, 68.126, 67.931, 68.806 | 68.256 |
| queue / strict / fast | 10.721 | 9.668 | 9.633, 9.598, 9.473, 9.314, 9.532 | 9.532 |

Baseline acceptance softened 3 demo-minimal, 5 demo-strict, 0 queue-minimal,
and 7 queue-strict findings. A comment-only edit reopened those same 3, 5, 0,
and 7 accepted entries respectively. The three demo-strict internal audit
findings remained errors even before that edit; baseline acceptance did not hide
them. Checks never wrote baseline bytes. This demonstrates adoption support and
its maintenance cost, not successful enforcement of the complete strict policy.

The public pilot is a separate sequential validation task, because running timing
assertions inside the parallel CI task would invalidate its registered
measurement conditions. Existing CI suites retain broader synthetic architecture,
coverage, selectors, guidance, and adoption proofs. This single-package public
sample does not establish inter-package architecture usefulness, external user
adoption, cross-platform runtime behavior, or AI-productivity benefits. The
latency gate passed on these inputs; authoring usability and broader release
claims remain limited as described above.
