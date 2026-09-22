# Milestone 7 adoption and suppression research

Research before implementation, 2026-09-21, source `b5cef5d`. The compiler was
`dev-2026-09:a2fb372b7` on macOS arm64. A separate binary was freshly built from
`odx/` with the repository's vet/style flags; the observations below were reproduced
with it. This is a synthetic adoption exercise based on the minimal example,
not evidence of an external adopter.

## Observed adoption behavior

The temporary project disabled compiler-dependent policies, copied the minimal
example's two local rules, changed the mutable package declaration rule to a
warning, and began with `old: int` in package `lib`. These are native-source
policy experiments; no successful source-only check is described as compilation.

| Experiment | Observed result before milestone 7 |
| --- | --- |
| One warning | `check --json` exits 0, `summary.warnings: 1`, complete source evidence. |
| Same warning with `--strict` | Exits 1; severity remains `warning`. |
| `baseline regen`, then strict check | Exits 0; finding remains visible with `baselined: true`; warnings count is 0 and baselined count is 1. |
| Add `new: int` while old declaration remains | Strict exits 1, one unbaselined warning and one baselined finding. Ordinary check exits 0. |
| Suppress old declaration with a reasoned directive | Finding disappears and `summary.ignored` becomes 1. CI exits 2 because the baseline entry is stale. |
| Same suppression with `--fast` | Exits 0, reports incomplete coverage, retains baseline bytes. |
| `ignores --stale --json` with that stale baseline | Exits 0 with no output and silently removes the baseline entry. |
| Remove literal `reason:` from an otherwise long directive | Directive still suppresses. The documented syntax is not enforced. |
| Keep suppression but replace mutable declaration with a constant | `odx/stale-ignore` is an error, including when the suppressed policy's severity is warning. |
| Introduce malformed procedure syntax | `check --json` exits 1 with `odin/syntax` and incomplete coverage; baseline bytes remain unchanged. |
| `ignores --stale --json` with malformed syntax | Exits 0 with no output, concealing the failed analysis. |

The failure case distinguishes source invalidity (a finding, exit 1) from a tool
failure (exit 2). An audit that promises to identify stale suppressions cannot
interpret either missing evidence or an empty result from failed analysis as a
successful audit.

## Compatibility and local consumers

README's adoption section, CLI usage, baseline source comments, and the milestone
0 contract explicitly promise automatic shrinking on full ordinary checks and
stale-baseline failure without rewriting in CI. These are documented contracts
even though the repository has no checked-in baseline adopter.

`check --json` schema 1 exposes severity, baseline status, summaries, and coverage;
`blocking: true` is explicitly a compatibility value, not the exit decision.
`finalize` counts findings before output truncation and gives tool errors priority.
Those contracts should survive baseline changes. Existing unit tests exercise the
warning/strict/baseline cross-product and error precedence; milestone 6's CLI probe
uses strict checks. Compiler findings preserve actual warning severity in
`odincheck.odin`; deleting warning support would also lose diagnostic fidelity.

The actual checked-in CI workflow calls `mise run ci`. Its self task runs
`doctor --ci` and an ordinary `check`; tests call checks and baseline operations.
The hook calls a fast check, always exits 0 as documented, and reports findings
and coverage. Its fast mode currently prevents baseline pruning. The installed
Claude settings contain no active hooks. No local consumer was found parsing
`ignores --stale` output. This says nothing about external scripts or users.

`cmd_ignores` currently ignores the result of `run_checks` in stale mode, then
prints only stale-ignore findings. That explains both the mutation and failure
concealment. The global usage advertises `--json` for ignores, but stale mode
ignores it. Ordinary `ignores --json` returns `{ignores, bad}`.

Suppressions run before baselines. They remove accepted findings; baselines soften
remaining findings. A line directive applies to all matching findings at its
target line, not literally only one finding as the README implies. File directives
apply across the file and can suppress package findings for that package. Suppression
scope is intentionally broader than an occurrence baseline and needs honest prose.

## Approaches and recommendation

| Approach | Benefits | Costs and compatibility |
| --- | --- | --- |
| Preserve warning/error plus strict, baselines, and reasoned suppressions | Gradual adoption without disabling an entire rule; compiler warning fidelity; targeted documented exceptions. | More combinations, but current code already handles most correctly. Selected. |
| Collapse severity and require immediate compliance or local suppressions | Fewer combinations and no debt ledger. | Breaks documented warning behavior and forces annotation noise or wholesale rule disabling in existing projects. Rejected. |
| Retain automatic shrinking, make every audit explicitly nonmutating | Preserves ordinary-check convenience and current documented behavior. | Every new check caller must remember mutation semantics; editors and CI differ. Credible but less predictable. |
| Make checks read-only and provide explicit baseline maintenance | Deterministic ordinary/CI behavior; mutation is a deliberate reviewable action. | Requires explicit migration documentation and a new maintenance step for users relying on automatic shrinking. Preferred. |

Retain both severities and strict mode without changing JSON schema 1. Preserve
the distinction between warnings, accepted baseline debt, local suppressions,
and incomplete evidence. Repair stale-suppression audit so JSON output exposes
coverage/failures and the command cannot silently report success when evidence
is incomplete. Preserve a useful text listing while specifying audit exit codes.
Require the literal `reason:` marker; explicitly document that malformed legacy
directives become `odx/bad-ignore` and show the one-token repair.

Meaningful implementation acceptance should cover ordinary and strict warning
exits, baselined warnings, a newly introduced warning under a baselined rule,
suppression-before-baseline behavior, stale suppression, missing reason marker,
output truncation preserving aggregate failure, and nonmutation plus honest
failure output for `ignores --stale` in text and JSON modes. Baseline identity and
format migration require the separate baseline research's adversarial scenarios.

Revisit severity simplification only with a demonstrated user cost exceeding the
adoption and compiler-fidelity benefit. Revisit automatic mutation only with
concrete workflow evidence, not the absence of a repository-local baseline file.

## Implementation validation

The selected fixes require the literal `reason:` marker and make
`ignores --stale` a read-only audit that bypasses baseline application. It prints
the complete check report, including unrelated findings, in text or schema-1
JSON. Exit 0 means complete evidence with no malformed or stale suppressions;
exit 1 means malformed/stale suppressions; exit 2 means incomplete evidence or
tool failure. Unrelated policy findings do not fail this audit. Ordinary
`ignores --json` retains its existing `{ignores, bad}` structure.

A fresh private build with the repository's full vet/style flags passed. The
reason-marker unit test passed, including the adversarial case where `reason:`
appears later in a malformed explanation. The dedicated CLI probe passed 46
assertions against the integrated version-2 baseline implementation: warning
and strict behavior, visible accepted warnings, new debt in another file,
truncation counts, suppression precedence, invalid/stale suppressions,
read-only text/JSON audits, native parse failure, and unavailable compiler
evidence. These are focused results; the final milestone record owns full-CI
validation. The probes remain synthetic and do not establish external adoption.
