# Milestone 4 diagnostics research

Research date: 2026-09-21. Read the complete roadmap and inspected report,
checks, coverage, baseline, suppression, hook, rule-authoring, JSON consumers,
README, and existing evidence runners. The reference compiler reports
`dev-2026-09-nightly:a2fb372`; research rebuilt the current sources with that
compiler as `/tmp/odx-m4-diagnostics` using `-vet -strict-style`.

This is preimplementation evidence and a recommendation, not a completion claim.

## Observations

`check --root tests/fixtures/contract --fast --json dependencies_r3` reports
`dependencies/R3` at `dependencies_r3/fires.odin:4:1`. Its statement says to pass
state as a parameter, while `fix_hint` says “Package-level state read and written
from several procedures.” `checks.odin` directly assigns `instead_of` to
`fix_hint`. The same reversal exists for allocator tags and result attributes.
The desired code is present separately in the `silent` example, but a consumer
following just the machine repair field receives the discouraged practice.

A fresh temporary project with compiler-valid `state: int`, a custom `domain`
role, and a local warning-level mutable-declaration rule produced:

| Invocation | Exit | Coverage complete | Warning count | Baselined count | `blocking` |
| --- | --- | --- | --- | --- | --- |
| Full check | 0 | true | 1 | 0 | true |
| Full `--strict` | 1 | true | 1 | 0 | true |
| `--fast` | 0 | false | 1 | 0 | true |
| Full strict, matching baseline | 0 | true | 0 | 1 | true |

The custom rule's `fix_hint` was “Mutable globals.” in all four runs. Thus
severity, baseline state, completed evidence, and process failure are already
independent concepts. README's “0 clean” shorthand is misleading for warnings,
accepted debt, and skipped checks. `blocking` is explicitly retained as an always
true schema-1 compatibility field, including warnings and accepted debt.

Suppression removes matched findings before final output and increments
`summary.ignored`. Baselining retains findings, sets `baselined`, and excludes
them from error/warning counts. Coverage finding counts are collected before
both operations. Partial or failed checks do not shrink a baseline. Full CI
rejects stale entries with tool error 2; ordinary complete checks may shrink them.
Milestone 7 owns any redesign of these adoption semantics.

Finalization counts before truncation, so `--max-violations` cannot change the
exit outcome. Tool errors take precedence over violations. Existing unit tests
cover truncation and accepted debt, but do not directly establish the full warning
matrix above. Hooks print human guidance and always exit 0 after configured
invocation. `--json` is not consumed by `cmd_hook`, despite broad help wording.
Avoid promising a new hook JSON interface merely as part of a repair-field fix.

## Consumers and compatibility

Repository consumers are README, generated `CLAUDE.md` prose, `report_text`,
`hook_text`, and Odin evidence runners. No repository code parses `fix_hint` or
`blocking` to execute a repair or decide success. Search found no external-client
inventory; absence of repository consumers cannot prove absence of users.
README promises schema 1 changes are additive and explicitly describes the old
`fix_hint` mapping. Correcting this semantic bug therefore needs a visible
compatibility note, not a claim that no behavior changed.

Credible choices are:

1. Keep the inverted field and add a differently named repair field. This avoids
   changing its value, but perpetuates the very misleading contract the milestone
   requires correcting and leaves existing agents on the wrong field.
2. Make `fix_hint` the rule statement, with no new authoring field. This is the
   smallest correction and preserves local files. Some statements express a
   prohibition rather than useful steps, and configuration-dependent rules need
   repair wording separate from normative policy.
3. Add optional, explicitly authored `fix_hint` to rule frontmatter, fall back to
   the existing statement for legacy local rules, and provide actionable built-in
   values. Retain schema number, types, old fields, and exit behavior. Add an
   `instead_of` finding field for the discouraged alternative. This is recommended.

Validate an explicitly supplied repair field as a nonempty string (whitespace
alone is empty); do not require all old local rules to migrate. Apply the same
validation to file trials and normal rule loading. The scaffold should explain
or include the field. Built-in hints should say to add the requested tag or
attribute, pass mutable state explicitly, or remove/restructure the offending
import in accordance with the configured role policy. No generic hint can promise
that a single edit resolves an indirect dependency without design work.

This keeps `statement` normative, `why` rationale, `instead_of` discouraged
practice, `fix_hint` corrective direction, and `silent` an executable example.
Author-provided language is still not mechanically proven to be an adequate
repair; rule tests prove example behavior, not arbitrary prose truth.

## Evidence and deterministic presentation

Findings already identify rule, file, position, message, statement, rationale,
and examples. Coverage limits currently require joining the finding to a
package/rule coverage row. Additive per-finding `evidence` and `boundary` strings
can use the existing `rule_evidence` function to keep JSON and human guidance
consistent. Keep evidence availability in coverage: an architecture rule may
report a known violating edge while another necessary edge is unsupported.
A finding's presence must not imply that its whole rule or scan completed.

Compiler/internal notes have no rule examples or corrective metadata. Do not
invent an automatic patch for compiler messages. They can carry an accurately
identified evidence source and explain that the compiler message supplies the
necessary correction context. For internal suppression/config notes, the existing
message generally gives the corrective action.

If adding an exit-related boolean, define it precisely as the finding's
contribution to a `check` invocation under strict/baseline policy; it is not the
hook's process status. Alternatively leave the legacy `blocking` field alone and
document the established severity/baseline/strict calculation. Adding ambiguous
`blocking` replacements is worse than making its compatibility status explicit.

`sort_violations` compares file, line, column, and rule only. Two imports or
multiple graph denials with the same reported location/rule need subject and
message tie-breakers for a total meaningful ordering. Current graph traversal
is sorted, but deterministic report ordering should not depend on producer
iteration order. Test equivalent findings supplied in opposite insertion order.
Raw ordering in other map-derived guidance belongs in the guidance investigation.

## Acceptance probes and limits

Positive repair probes should take the built-in hint's described action and
compile/check the result: parameterized mutable state, requested allocator tag,
requested result attribute, and compliant dependency edge. Negative probes should
show the discouraged forms still fire. Legacy local rules without the new field
must remain accepted; malformed repair metadata must fail. Custom repair wording
must survive local overrides and file trials.

Retain the observed warning/strict/baseline/partial matrix, tool-error precedence,
suppression count semantics, and hook exit 0. Verify truncation cannot alter
summary/exit results; verify per-finding boundaries match the corresponding
coverage descriptions. A valid finding plus incomplete graph evidence is an
adversarial case against marking the entire report clean merely because a repair
hint exists.

No new compiler API, parser dependency, or graph pass is needed. Metadata copies
add output bytes and negligible computation; more extensive text on every human
finding should be balanced against hook repetition, which already deduplicates
rule context. Cross-platform output and external clients remain untested. Revisit
schema versioning if a future change removes fields, changes types, or gives
`blocking` operational semantics. Revisit repair automation only with actual
edit safety and behavior proofs.
