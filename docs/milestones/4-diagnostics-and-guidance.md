# Milestone 4: accurate diagnostics and synchronized guidance

Completed 2026-09-21 using mise Odin `dev-2026-09-nightly:a2fb372` on macOS arm64.
The full roadmap was reviewed and three independent research agents completed
their investigations before implementation:
[diagnostics](4-diagnostics-research.md), [freshness](4-freshness-research.md),
and [Markdown ownership](4-markdown-research.md).

## Problem and evidence

`fix_hint` contained `instead_of`: dependencies/R3 told consumers to introduce
the mutable package state it prohibited. Existing generated instructions could
remain byte-identical after changes to error classification, compiler flags, or
package discovery. Output lacked selected-package identity. The old writer used
a heading substring to decide ownership and offered no freshness guarantee.
These affect diagnostic consumers and projects maintaining instructions alongside
human-authored Markdown. Research records retain the reproductions and primary
source references in the installed compiler/core libraries.

## Decisions and alternatives

**Repair metadata.** Repurposing `instead_of` would break rule authors' existing
meaning. Mandatory new metadata would break local topics. Instead, optional
nonempty `fix_hint` describes the desired action; older rules fall back to their
statement. All four active builtin rules now provide explicit repairs. Rationale,
discouraged alternative, and check evidence stay separate. Existing fires/silent
examples compile and demonstrate the corresponding policy correction; prose
hints are not an automatic refactoring guarantee.

**Compatibility.** Schema 1 retains existing names and types. Correcting the
inverted value is a deliberate semantic bug fix: consumers treating `fix_hint`
as discouraged behavior must use new `instead_of`. Additive finding fields
`evidence` and `boundary` identify the analysis and its limits. Compiler/internal
notes leave policy metadata empty. `blocking` stays reserved and always true;
it does not predict process exit. Warning-only runs exit 0 unless strict;
baselined findings remain visible and do not fail strict runs. Suppressions remove
accepted findings, truncation does not change counts/exits, and unavailable
required evidence still takes precedence with exit 2. Partial coverage can exit
0 and must be read independently. Hooks remain informational and exit 0.

**Freshness.** Raw file hashes would churn on comments and confuse embedded rules
with editable source. Comparing only the old rendered prose demonstrably missed
configuration changes. The selected approach compares one deterministic rendered
block, including a SHA-256 digest of normalized effective configuration, loaded
rule metadata/contracts, selected package paths/roles, explicit scope identity,
and generator revision. Sorted JSON map keys avoid insertion-order churn;
sequence order remains significant. Runtime source paths and unused exemplar
concatenations are omitted. Full effective config/rulebook hashing deliberately
permits conservative staleness for changes outside a package's displayed rules.
Generation performs normal project discovery/validation, without parsing source
bodies, launching a compiler, or consulting ODX_ODIN. Embedded edits require a
rebuild. The actual check-time compiler, baselines, and suppressions belong to run
evidence, not instruction freshness. Interpreter-only semantic changes require a
generator revision bump.

Readable output contains effective configuration and exact selectors, plus
per-rule applicability, correction, severity, evidence limits, and separately
labeled reviewer advice. This is more verbose than summary-only prose but makes
configuration-dependent policy reviewable. Scope selection uses milestone 3's
shared applicability functions. Global output is a union, not a claim that all
rules apply to all listed packages. Empty projects render a conditional catalog.

**Ownership.** Heading-to-next-heading/EOF replacement risks deleting human text.
Automatically refreshing during normal checks hides drift. Instead, explicit
`guidance check|write <markdown-file> [package-path]` owns exactly one versioned
marker pair. Check never writes: 0 current, 1 stale/missing, 2 invalid ownership,
configuration, or IO. Write replaces only the owned span or appends when absent.
Duplicate, reversed, unsupported, inline/fenced markers, unclosed fences, and
generated-marker collisions fail rather than guess. Legacy unmarked sections
require a human to delimit the generated span. The repository's old generated
section was explicitly delimited and regenerated during migration.

Existing permissions and all bytes outside the span survive updates. Same-directory
temporary writes check write/sync/close results before rename; symlink and
nonregular destinations are rejected. Repeated current writes avoid replacement.
There is no concurrent-editor locking, ACL/xattr preservation guarantee, or
directory-fsync power-loss guarantee. Windows/Linux runtime behavior remains
untested; the selected core APIs are portable, but only macOS was exercised.

`for --emit-md` and legacy `--emit-claude-md` share the same renderer. AGENTS.md
and CLAUDE.md receive identical policy blocks for identical scopes. No agent
vendor, hook, or model is required for enforcement or freshness.

## Acceptance evidence

`mise run --force ci` passed after the self-check caught and prompted correction
of a missing `@(require_results)` on the file replacement helper:

- 32 unit tests with address sanitizer and memory tracking, including warning /
  strict / baseline / partial-coverage matrices, deterministic finding ties,
  repair metadata validation, and ownership/permission/symlink tests.
- 105 milestone 4 CLI assertions: valid corrective JSON, both Markdown filenames,
  idempotence, human prefix/suffix preservation, check nonmutation, semantic
  config stability, error/flag/dependency/role/selector/override/disabled-policy
  divergence, package discovery, canonical scope aliases and scope mismatch,
  malformed ownership, legacy refusal, invalid config and directory errors.
- Existing 121 milestone 3, 113 milestone 2, and 49 milestone 1 CLI assertions.
  These retain selection/enforcement agreement, failure coverage, suppression,
  baseline, and incremental behavior counterexamples.
- Five fixture projects, every active rule fires/silent and reader example,
  four exemplar packages, compiler redundancy audit, and project self-check.
- Repository CLAUDE.md freshness now participates in CI. Two existing doctor
  warnings remain: missing hook integration and unused allocator topic roles.

Negative/adversarial cases include a policy change invisible to old prose,
same-value JSON5 comments/map order that must stay fresh, body-only source edits
that must stay fresh, sibling-package scope mismatches, duplicate ownership,
fenced marker collisions, and a symlink target that must remain untouched.

## Cost, limits, and revisit conditions

A local `/usr/bin/time -p build/odx guidance check CLAUDE.md` sample took 0.02s
wall time for this six-package repository; this is a sample, not a benchmark.
Generation scales with existing discovery plus policy serialization and document
size; no compiler subprocess, cache, or persistent index was added. The complete
CI rerun took about five seconds locally.

Freshness establishes synchronization with the running binary's effective policy,
not semantic equivalence of arbitrary author prose and selectors or proof of
runtime behavior. Error inference, allocator exemptions, and broader existing
policy claims remain milestone 5 work. Local rule repair prose remains authored
policy and cannot be proven correct by nonempty-string validation.

Revisit if real projects show unacceptable document size/discovery cost, need
multiple scopes in one file, depend on metadata-preserving concurrent writes, or
require other-platform atomic replacement guarantees. Revisit schema versioning
before removing fields or changing exit semantics; no such removal occurs here.
