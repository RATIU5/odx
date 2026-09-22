# Milestone 7: deliberate adoption and compatibility

Research completed before implementation in three independent investigations:
[baseline identity](7-baseline-research.md), [severity and suppressions](7-adoption-research.md),
and [obsolete setup and workarounds](7-cleanup-research.md). Source baseline was
`b5cef5d`; probes used Odin dev-2026-09 revision `a2fb372` on macOS arm64.
The scenarios are synthetic existing projects, not evidence of external users.

## Adoption decision

Keep warning/error severities, strict mode, baselines, local suppressions, and
public selectors. A project can first report a warning, enforce it with strict
mode, accept bounded existing debt, and require deliberate exceptions near code.
These are different workflows. Compiler warning fidelity and user-authored rules
would be lost by simplifying everything to one pass/fail severity.

Baselined findings remain visible in schema-1 JSON and text, retain their original
severity, and contribute to `summary.baselined` rather than unaccepted warning/error
counts. Strict mode fails unaccepted warnings. Suppressions remove matching
findings before baseline application. Output limits do not change the aggregate
exit decision. `blocking` remains a compatibility field, not a severity switch.

## Baseline identity and tradeoff

Version 1 accepted every finding sharing `(rule, package, subject)`. A single
accepted import or call could therefore grandfather newly introduced occurrences
in other functions and files. It also ignored malformed records and version
headers. Fresh compiler-valid examples reproduced these failures.

Version 2 uses one source occurrence: rule, relative file, subject, line/column,
and a SHA-256 snapshot of the complete source file. An entry is consumed at most
once. Rule metadata can still prohibit baselining. Findings without a usable
source-file identity, including package-directory findings, are ineligible.
`subject` remains useful report metadata but is no longer described as the entire
baseline key.

The JSON document has `format_version: 2` and `entries`. Every entry contains
`rule`, `file`, `subject`, `line`, `col`, `fingerprint` (lowercase SHA-256 hex), and
`reason` (possibly empty). Unknown/missing fields and invalid identities are
errors. Duplicate records are explicit multiplicity: each accepts at most one
matching occurrence, and unmatched copies are stale. Add/prune retain reasons;
regeneration starts a fresh set. Writes use a unique temporary file in the same
directory, preserve existing permissions, and replace the destination atomically.

This is deliberately conservative: any source-file edit reopens its findings,
including comments, formatting, line shifts, argument changes, and enclosing
procedure renames. Acceptance cannot move across files or changed source merely
because a call has the same name. Deleting and recreating byte-identical source
at the same identity remains indistinguishable; no historical identity is claimed.
Unchanged files keep their accepted occurrences when other files change.
Identity binds the rule ID, not the historical meaning of a local rule under that
ID. Changing a rule's contract requires reviewing its accepted debt; use a new ID
when old acceptance must not transfer. Compiler versions and policy text are not
historical identity records in this format.
Changes only in dependencies can also leave the originating source occurrence
accepted. This ledger binds source occurrences, not the historical behavior of
the entire dependency graph; review affected acceptance when dependency policy
or dependency behavior changes.

| Identity alternative | Benefit | Cost and decision |
| --- | --- | --- |
| Subject buckets with counts | Small, movement tolerant | Can exchange old debt for new debt in the same bucket; rejected. |
| Declaration anchors and normalized token context | Better tolerance of formatting and unrelated edits | Needs reliable anchors for compiler/native findings, nested and anonymous procedures, inactive declarations, and duplicates; defer pending demonstrated reacceptance cost. |
| Position plus source-line digest | Small, distinguishes many changes | Misses enclosing-procedure changes that leave a call's line unchanged; rejected. |
| Exact occurrence plus whole-file snapshot | Simple evidence, conservative new-debt boundary | Reacceptance churn within edited files; selected and explicitly documented. |

Snapshot matching is an adoption correctness choice, not a claim of ideal
large-project ergonomics. Revisit normalized anchors when real projects show
unacceptable churn, keeping the cross-file, cross-procedure, and duplicate
counterexamples as regression requirements.

## Explicit lifecycle and migration

Ordinary `check`, CI checks, hooks, and suppression audits do not rewrite the
baseline. A full complete check reports stale acceptance as a tool error in both
ordinary and CI modes and directs the author to explicit maintenance. Partial
or failed checks cannot judge debt resolved or erase entries. A stale-baseline
tool error makes aggregate coverage incomplete under the existing report contract;
individual source/compiler coverage entries still describe what was analyzed.

| Command | Intended mutation |
| --- | --- |
| `baseline add` | Retain existing entries/reasons and accept currently unmatched eligible occurrences. |
| `baseline prune` | Remove entries not matched by a complete whole-project scan; never accept new debt. |
| `baseline regen` | Replace the file with acceptance of current eligible findings; this is a fresh adoption decision. |

All writes require complete whole-project analysis. Normal checks are read-only
even when stale entries exist. Source-invalid, unavailable compiler, unsupported
graph, and malformed configuration cases preserve existing bytes. Read/write
errors and nonregular baseline paths cannot be interpreted as an absent baseline.

Version 1 cannot be migrated faithfully because it never stored occurrences.
Checks, add, and prune reject it; explicit regeneration accepts current findings
into version 2. Regeneration does not reconstruct historical acceptance or carry
old reasons across ambiguous identities. Review both the current findings and
the baseline diff. Unsupported/malformed baseline input fails closed rather than
silently accepting or dropping debt; explicit regeneration is the recovery path
for readable regular files after successful analysis.

The previous README promised automatic shrinkage, so removing that behavior is
an intentional compatibility change. Local CI and hooks were inventoried; no
checked-in adopter depends on automatic shrinkage. That absence is not proof
about external users. Users relying on it must add explicit prune maintenance.
Immediate compliance or widespread local ignores were considered but would make
established-code adoption unnecessarily difficult.

## Suppression auditing

The documented literal `reason:` marker is now required. Previously an arbitrary
ten-character suffix could suppress a finding despite omitting it. Such legacy
directives now produce `odx/bad-ignore`; insert `reason:` to preserve the intended
exception. A line ignore applies to matching findings for that rule on its target
line, not necessarily one occurrence. File ignores can cover all matching findings
in the file; this broader deliberate exception is distinct from baseline identity.

`ignores --stale` previously ignored analysis failures and silently inherited
ordinary-check baseline writes. It is now a read-only specialized audit:

- Exit 0: complete evidence, no malformed or stale suppression.
- Exit 1: malformed or stale suppression.
- Exit 2: required evidence incomplete or a tool error.

JSON returns the schema-1 check report, including coverage and diagnostic evidence.
Unrelated policy findings remain visible but do not by themselves fail this
audit. Baselines are not applied, since acceptance does not determine whether a
suppression matched. Ordinary `ignores --json` retains its `{ignores, bad}` listing.
This changes the previously empty/stale-only success output intentionally; scripts
must distinguish the specialized audit status from a project policy verdict.

## Justified cleanup and retained surfaces

Initialization no longer appends `.odx/cache/` to a user's `.gitignore`. There is
no cache reader/writer or invalidation mechanism; the write was obsolete setup.
The repository's unused entry was removed. Existing user ignore entries are left
alone. Reintroducing caching requires measured demand and explicit invalidation.

Documentation fields (`why`, `evidence`, `cost`, `instead_of`), reader advice,
example roles, all five public matchers, and schema compatibility fields remain.
They have actual authoring/reporting consumers; absence from the built-in catalog
is not a removal argument. Scaffold evidence guidance now accepts reproducible
source-policy findings on compiler-valid examples, not only compiler failures.
The separate comment-only review corrects stale enforcement, callee-identity,
complexity, and evidence claims; details and counts are in the cleanup record.

Twenty default-threaded checks and twenty doc exports succeeded during research.
That does not disprove earlier intermittent empty-stderr crashes, so bounded
compiler retries remain. Literal scaffold substitution also remains: formatting
the JSON5 template still reproduces missing-argument/brace output with the pinned
`fmt` implementation. No public rule, metadata field, severity, or compiler
workaround was removed without evidence.

## Validation

The retained [baseline](7-baseline-probe/main.odin),
[adoption](7-adoption-probe/main.odin), and [cleanup](7-cleanup-probe/main.odin)
CLI probes run through `mise run adoption`, included in full CI. They exercise
existing debt, new/resembling occurrences, symbol/source changes, malformed and
legacy formats, explicit maintenance, warning/strict behavior, suppressions,
failed/partial analysis, and initialization side effects.

Final `mise run --force ci` passed on the pinned compiler:

- 37 unit tests with address sanitization and memory tracking.
- 190 baseline CLI assertions and 46 adoption/suppression assertions, plus the
  initialization preservation probe.
- Earlier milestone probes: 49 evidence, 113 architecture, 121 selector-contract,
  105 guidance, 58 error-semantics, 45 allocator-semantics, and 164 policy assertions.
- All fixture projects, built-in rule/reader examples, four exemplar packages,
  and the compiler redundancy audit.
- Repository and both example guidance files current at generation 3.
- Self-check: 54 files, complete evidence, no findings. Doctor retains its two
  existing warnings about hook configuration and unused allocator reviewer roles.

The initial integration run correctly rejected an old version-1 baseline fixture
in the milestone 1 evidence probe. That preservation fixture now uses version 2;
dedicated milestone 7 tests cover legacy rejection and explicit regeneration.
`git diff --check` passed. The ignored local roadmap was marked through milestone 7.

Other platforms/toolchain versions,
external automation compatibility, and acceptable snapshot reacceptance cost on
large projects remain unproven. Milestone 8 owns external usefulness and release
decisions; this milestone establishes the bounded adoption contracts.
