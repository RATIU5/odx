# odx roadmap

## Purpose and boundaries

Keep odx a small deterministic companion for project-owned Odin policies, with
concise evidence for humans and external coding agents. External agents make
edits; odx never calls a model. Compilation, test execution, formatting and editor
services belong to the Odin compiler, existing build tools, odinfmt and OLS.

odx is a constraint oracle: what an agent consults before writing Odin, and what
evidences compliance after. The compiler owns "is this legal Odin"; nothing owns
"is this legal *here*". Serve that, or the two moments around it, or do not build it.

Findings reach consumers as data an agent applies, not as instructions it must
follow. Reliable instruction-following degrades past a handful of simultaneous
constraints, so the resident policy block is a cost, not a feature: prefer scoped,
on-demand answers and machine-applicable repairs. See RESEARCH.md.

Add capabilities only for concrete project requirements. Reuse compiler evidence
and existing tools before implementing another analyzer. No generic query
language, new backend, preset framework, server, plugin runtime or embedded agent
integration is justified by this roadmap. Normal checks remain read-only.

The build is experimental: assessed on macOS arm64 with the pinned September 2026
Odin toolchain; Linux CI is configured. Broader platform/toolchain support,
first-time policy authoring cost and independent adoption still need evidence.
No agent-productivity benefit is established.

## Implemented foundation

These are existing capabilities to preserve and extend, not pending milestones:

- `check`, scoped `policy` context, managed instruction generation/verification,
  baseline maintenance, and suppression inventory/staleness auditing.
- Project-defined roles, dependency boundaries and local Markdown policy topics.
  Local topics replace built-ins; reviewer advice is separate from checked rules.
- Native Odin AST/token checks: call/import/proc/decl/foreign patterns and the
  opt-in compact-if selector, plus allocator-directive and file-tag audits.
  Compact-if already has native positive/negative and whole-project tests.
- Compiler diagnostics and compiler entity evidence for result-attribute checks.
  Entity export is not a resolved reference or call graph.
- Direct import allow rules and transitive deny rules with dependency chains.
  Syntax-only checks avoid unnecessary project-wide graph work; dependency checks
  load full project evidence while reporting only the selection.
- `analyze(Analysis_Options) -> (report, exit_code)` without printing or exiting.
  The CLI validates options and renders results. JSON schema 2 shares rule metadata,
  reports evidence coverage, and rejects invalid arguments/configuration.

Start from [README.md](README.md), [analysis.odin](odx/analysis.odin),
[check_contract.odin](odx/check_contract.odin),
[import_graph.odin](odx/import_graph.odin) and [report.odin](odx/report.odin).
README and executable tests own the current public contracts. The following work
is unimplemented; proposed capabilities do not reserve command names or APIs.

## Prioritized work

### 0. Evaluation harness — blocks everything below

A previous harness measured odx *regressing* agent compile and test rates and was
deleted without isolating a cause. Two mechanisms predict that result independently:
instruction density from the resident policy block, and repair driven by a proxy
signal rather than ground truth. Until they are separated, no item below is decidable.

Factorial design, paired tasks, hard mechanical outcomes only, and a budget-matched
control that spends the same tokens on resampling. `odx` finding counts are a
manipulation check, never a quality claim. No model-as-judge. Pre-register the
analysis. Full plan in [HARNESS.md](HARNESS.md); evidence in [RESEARCH.md](RESEARCH.md).

Acceptance: a committed pre-registration, results as raw rows, paired tests with
confidence intervals, and a written conclusion that is allowed to be negative.

### 1. Applicability and machine-applicable repairs

Add an applicability grade to every finding, and a structured repair distinct from
the existing prose `fix_hint`: byte range plus replacement, with an explicit
safe/unsafe split where unsafe requires opt-in. A consumer applies a safe repair
with no model involved; the prose field keeps its current contract and audience.

Ship two repairs first, not twenty: the compact-switch directive, and the result
attribute together with its call-site cascade — emit the whole cascade or none of it.

Never emit a repair that changes a procedure signature, and never one that inserts
deferred release: escape behaviour is not syntactic, and an incorrect release
converts a detectable leak into memory corruption. Record that as policy, not a TODO.

Acceptance: schema addition with version handling; `fires`/`silent` blocks extended
so a repair must produce byte-identical expected output and silence the rule;
unsafe repairs absent by default; no repair emitted when its precondition is
unverifiable.

### 2. Scoped, on-demand constraint answers

Extend `policy` so a consumer can ask what applies to one path and receive the
resolved import allowances, applicable rules with scope, and the exact suppression
syntax — rather than reading a whole-project block. Keep simultaneous constraints
small. This is an extension of an existing command, not a new one.

Acceptance: path-scoped selection; resolved allow/deny closure rather than echoed
configuration; stable documented JSON; unchanged behaviour for existing invocations.

### 3. Rule library: contradiction over convention

Grow rules only where the code entails its own violation — a procedure that accepts
an allocator and does not forward it is a contradiction within one procedure, needing
no corpus and no adherence statistic. Rules derived from how often a corpus happens
to do something are not this, and measurement of the Odin standard library found its
strongest regularity at roughly 85% with principled counterexamples.

Every rule must answer "why can't a compiler flag do this?" in one sentence, because
a rule the compiler could absorb is a depreciating asset. Anything resting on
allocation, ownership, lifetime or escape behaviour is not syntactic and belongs in
reviewer advice. Local rule authoring and the example policies carry the opinion;
built-ins stay minimal.

Acceptance: positive/negative blocks per rule; a stated compiler-absorption answer;
measured noise on real Odin source before any default changes.

### 4. Certified exemplar selection

`check` can certify which source is rule-clean, which makes an exemplar pool correct
by construction rather than by heuristic. Expose a way to select certified examples
of a construct. Rules state what to avoid; examples state what to produce, and for a
language with little training presence the second carries more signal.

Acceptance: deterministic selection; certification tied to complete evidence;
no new analysis engine.

### 5. Finding comparison, narrowed

Distinguish introduced from inherited findings so an agent working in a repository
with existing debt is told what it made worse, not handed a wall of pre-existing
findings. Begin and end with findings; metric deltas depend on measurements that do
not exist and are not planned.

Keep comparison identity separate from accepted-baseline identity. Define base
selection, committed versus worktree inputs, analyzer/compiler compatibility. Line
movement alone must not introduce a finding; ambiguous matches must not hide new
debt; failed base analysis must not become a clean comparison. Historical analysis
must preserve the worktree and not execute repository build scripts.

Acceptance: unchanged debt in edited files, new occurrences of an existing rule,
renames/deletions, policy changes, untracked inputs, unavailable history. Compare
complete results before truncation. Do not repurpose `--since` or mutate acceptance.

### 6. CI report formats

SARIF and concise Markdown as renderers over the existing report, carrying rule IDs,
locations, severity, provenance, acceptance state, tool errors, incomplete coverage
and — once item 1 lands — repairs with their applicability. Counts remain correct
after truncation. Bounded work that can ship independently.

### 7. Toolchain feature detection

Replace assumptions about a pinned nightly with detection: probe available compiler
capabilities, record what was detected in coverage, and degrade to unsupported with
a reason instead of failing. This fits the existing evidence-status model and turns
the project's sharpest fragility into reported evidence.

Acceptance: recorded detection in coverage output; explicit unsupported status;
no silent behaviour change across toolchain versions.

### Deferred, with reasons

- **Architecture-change reporting.** Added/removed package edges and reverse-import
  impact remain plausible, behind the items above. Reuse the source graph; do not
  conflate it with compiler build scope. Import impact means potential package
  impact, not a resolved call graph.
- **Procedure complexity metrics.** Would need a counting contract defined before
  implementation and noise evaluation on real projects. A measured value does not
  tell a consumer what to change. Optional and project-local if a user asks.
- **Duplication detection.** Withdrawn. It needs a second analysis engine, its own
  clone identity and multi-location acceptance semantics, and matching token
  sequences in Odin can differ materially in allocator, cleanup and error behaviour,
  so a consumer cannot act on the finding safely.
- **Churn-informed ranking.** Withdrawn. Advisory ranking does not answer the
  allowed/forbidden question a consumer needs.
- **Editor and harness integrations.** Editor services belong to OLS. A tool-calling
  wrapper adds no capability the CLI and its JSON lack; an existing Odin analyzer
  shipped one to no effect. Revisit only if the harness in item 0 shows delivery
  mechanism changes outcomes.
- **Commit-blocking gates.** Rejected on the escape-hatch principle: odx reports and
  adds friction; wiring that into a gate is the project's decision, not odx's.

## Cooperate with the toolchain

Do not implement standalone unused-code reachability. Odin already exposes
`-show-unused`/`-show-unused-with-location` and specific unused vet flags. Plain
`-vet` does not include `-vet-unused-procedures`; configured flags already flow
through odx with derived `-vet-packages`. Improve examples/documentation when that
is sufficient. Formatting, reference navigation, runtime memory diagnostics and
test execution remain with existing tools.

A future unused-declaration report, if requested, should adapt compiler evidence.
It needs explicit application/library roots and build configurations: current
per-package checks use `-no-entry-point`, which changes reachability. On the assessed
compiler the unused listing remains text stdout with `-json-errors` and does not
itself fail the check. Respect exported/required/initialization roots; no visible
Odin caller does not establish that an external API is removable. Reverify compiler
capabilities on the pinned version before adding an adapter.

## Contracts every increment must preserve

- Paths select packages. `--since REF` considers relevant current-worktree changes,
  including untracked inputs, then checks the full current project. No relevant
  changes means empty, incomplete coverage; it is not a new-finding comparison.
- Native checks inspect collected inactive/platform/test source; compiler checks
  cover the selected build. Required failed, skipped or unsupported evidence stays
  explicit. Exit 0 and `coverage.complete` are not proofs of correctness.
- Dependency tests do not propagate production edges; selected package tests count.
  Unconfigured toolchain collections are opaque leaves. Required missing, excluded,
  unknown-collection or outside-project edges remain unavailable evidence.
- Baseline acceptance binds rule, file, subject, position and whole-file SHA-256.
  Any source edit reopens acceptance. Writes require complete whole-project evidence
  and explicit maintenance; checks never rewrite acceptance. Preserve stale/malformed
  baseline and suppression audits, including their unavailable-evidence behavior.
- Findings retain severity and acceptance state. Warnings fail only with `--strict`.
  Check exits remain 0 for no failing unaccepted findings, 1 for findings, 2 for
  tool/configuration errors. Summary counts precede output truncation.
- Source predicates do not prove allocation freedom, ownership, lifetime, runtime
  purity or correct error handling. `@(require_results)` establishes acknowledgement,
  including explicit discard. Reviewer advice must not masquerade as a check.
- Keep analysis independent of rendering and process exit. Extend shared selector
  validation, metadata and coverage rather than parallel rule systems. Version
  incompatible output changes explicitly. Preserve atomic managed writes, instruction
  ownership, surrounding content and freshness rules; freshness is not compliance.

## Validation and adoption

Update README contracts and executable positive/negative examples with each feature.
Retain scope, applicability, unavailable-evidence, suppression and baseline regressions.
Use native unit/fixture and whole-project integration tests for observable behavior,
and the compiler for semantic assertions. Keep implementation bounded and maintainable;
add no framework for hypothetical future checks.

Run `mise run test` for native/compiler/integration tests and instruction freshness;
`mise run ci` also runs the repository self-check. Run `mise run validation`
separately when analysis changes need evaluation on pinned external projects.
Measure noise, authoring effort and performance before broadening defaults or making
adoption claims. Verify additional platforms/toolchains explicitly. Keep enduring
contracts in README and tests; do not accumulate research logs here. Current findings
live in [RESEARCH.md](RESEARCH.md) and retire once absorbed, as earlier milestone
research did.

Claims about agent outcomes require the harness in item 0 and a budget-matched
control. Conformance to project policy and correctness of the resulting code are
separate claims; evidence for one is not evidence for the other.
