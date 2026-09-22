# Milestone 7 baseline adoption research

Research completed before implementation, 2026-09-21. This records the old
implementation's behavior, not the final milestone contract.

## Evidence and reproduction

Built current source independently with `odin build odx
-out:/tmp/odx-m7-research -vet -vet-tabs -vet-cast -strict-style
-warnings-as-errors -vet-packages:odx -debug`. Toolchain: Odin
`dev-2026-09:a2fb372b7`. Temporary project `/tmp/odx-m7-adoption-research`
copied the minimal policy's configuration and local topics. No repository binary
or source was changed for these experiments.

`baseline.odin` currently keys entries by `(rule, package, subject)`. It marks
every matching finding, with no occurrence limit. `baseline add` deduplicates
these keys. Thus one accepted call permits any number of calls with that spelling
anywhere in the package. A subject is useful diagnostic metadata but does not
identify an occurrence.

Observed CLI outcomes:

| Experiment | Outcome before implementation |
| --- | --- |
| `old: int`, minimal mutable-declaration rule | Check exits 1; `baseline regen` creates one entry; subsequent CI check exits 0 with one visible baselined finding. |
| Rename `old` to `new` | New subject remains an error. CI exits 2 for the stale old entry. Ordinary check exits 1 and silently deletes the old entry. |
| Same rename with `--fast` | Exits 1, incomplete coverage, baseline bytes unchanged. |
| Replace declaration with malformed `old:` | Parser finding remains unbaselined; coverage incomplete; ordinary check preserves baseline. `baseline regen` exits 2 and preserves baseline. |
| Baseline one `panic("old")`, then add `panic("new")` in the same procedure | Both call findings become baselined from the single entry. The unrelated compiler unreachable-code finding remains an error. |
| Add a third `panic` in `Other` in a different file in the same package | All three call findings become baselined. |
| Baseline `core:fmt` import in `a.odin`, then add the same import to `b.odin` | CI exits 0 with two baselined findings from one entry: a demonstrated clean-build grandfathering failure. |
| Replace header with `format_version: 99` | Accepted silently; still exits 0 and softens both imports. |
| Append malformed non-tabbed line | Accepted silently; CI remains clean; malformed line remains until a rewrite. |

The call selector was copied from
`tests/fixtures/constructs/.odx/topics/local/R3.odx.md`, removing its role
exception. For imports its check was changed to
`{kind: "pattern", match: "import", name: "core:fmt"}`. Imports were used by
`fmt.println` procedures, so the successful import reproduction was compiler
valid. The call result deliberately distinguishes baseline matching from the
compiler's separate unreachable-code error.

Static inspection adds these lifecycle facts: only complete, full checks prune;
path, topic, fast, and since selections cannot prune. Parser failures therefore
retain debt. However read errors are all treated as “absent,” version headers are
not validated, malformed lines are skipped, and `baseline add` invokes ordinary
check application before deciding whether the command may write. Reasons can be
lost in regeneration. README explicitly documents automatic shrink and CI
failure; that is a compatibility obligation even though no repository adoption
file or external consumer evidence establishes dependence on it.

## Identity alternatives

1. **Package/file + subject + occurrence count.** Small and resistant to source
   movement; prevents an increase in total debt. Still transfers acceptance from
   a deleted call to a newly introduced call in another procedure, and package
   keys transfer across files. Counts alone fail the requested identity boundary.
2. **Rule + file + subject + enclosing declaration + normalized token context,
   with each entry consumed at most once.** Better movement/format tolerance and
   rejects calls in newly named procedures. Requires defining context for every
   native/compiler rule, duplicate declarations in conditional branches,
   anonymous/nested procedures, foreign blocks, and package-level diagnostics.
   Token context and counters still cannot establish historical identity when
   one indistinguishable occurrence replaces another.
3. **Rule + file + subject + source position + source evidence, consumed once.**
   Conservative and implementable using current findings. A source-line snapshot
   rejects changed arguments on that line, but misses enclosing-procedure
   renames when the call line and position are unchanged. A whole-file digest
   removes that ambiguity at the cost of reopening all accepted findings in an
   edited file. Position alone has that rename weakness and should not be
   described as semantic identity.

Recommend the conservative third approach if normalized AST anchors cannot be
implemented and validated within this milestone. Whole-file digest plus exact
position is the smallest strong conservative boundary: any edit to the source
file reopens its findings. This is less convenient for incremental adoption,
but explicit and reviewable, and has no accidental cross-file or cross-symbol
transfer. Alternatively choose the second approach only with tests for its
enclosing-declaration and duplicate-occurrence boundaries. Do not merely append
a file name or occurrence ordinal to the current broad subject key and claim
new occurrences are distinguished.

Keep `subject` in JSON as meaningful rule metadata; describe the actual baseline
identity separately. Non-source/package findings need a defined identity or must
remain ineligible. Findings without usable subjects/evidence remain ineligible.
Consume baseline entries once even if two findings have identical keys. No
snapshot-based approach distinguishes deleting and recreating byte-identical
source at the same identity without history. Document this limit explicitly.

## Lifecycle and migration decision

Compare retaining automatic shrink (less maintenance, existing contract) with
non-mutating checks plus explicit pruning (predictable review/CI and no write
side effects from check consumers). Recommend non-mutating checks. Preserve CI
stale-entry failure if desired for compatibility, and direct users to an explicit
prune command; ordinary check can report stale entries without rewriting. Prune
must require complete whole-project evidence and retain reasons, while regen is
explicitly a fresh acceptance of every eligible current finding. Add should
preserve existing entries/reasons and accept only the currently unaccepted debt.
All write commands must validate analysis and existing file before any mutation.

Use a new format version and strict parsing: invalid headers, unknown versions,
malformed records, duplicate identities, and unreadable existing files must fail
with a repair message and preserve bytes. Version 1 cannot be migrated faithfully
from its broad keys because historical occurrences were never stored. Require
explicit regeneration (with a message that it accepts current findings), or
provide an explicit migration command with that same disclosed limitation.
Ordinary check must not silently turn v1 entries into v2 acceptance. A dedicated
migration is more machinery than needed unless preserving historical reasons is
shown to matter. If regen can replace malformed files, that recovery behavior
must itself be explicit; it must not accidentally treat read errors as absence.

## Acceptance fixture plan

Retain a synthetic adoption project using a local import/call restriction and
mutable-declaration rule. Assert visible baselined counts and exit codes for
existing debt; same-file and cross-file new calls/imports; renamed symbols;
changed call arguments; duplicate occurrences; moved/formatted source according
to the chosen conservative contract; stale entries and explicit prune; reason
preservation on add/prune; and intentional growth through add/regen. Assert
baseline byte equality after ordinary, CI, strict, fast, topic, path, no-change
since, failed parser, failed compiler, invalid configuration, and failed
baseline-write attempts. Validate old-version refusal, explicit replacement,
unsupported versions, truncated/malformed records, delimiter characters, and
duplicate keys. CI stale failure must not accidentally claim analysis failed
merely because debt cleanup is pending unless that existing coverage contract is
deliberately retained and documented.

These are synthetic correctness proofs, not evidence of external adoption or
acceptable maintenance cost on large changing files. Reconsider conservative
identity when a real project demonstrates excessive reacceptance churn; retain
the cross-procedure/cross-file and replacement counterexamples when refining it.

## Implemented outcome and validation

The selected v2 identity uses rule ID, relative source file, subject, line,
column, and SHA256 of the complete parsed source file. Package-directory
diagnostics remain ineligible because no single source snapshot represents their
evidence. Rule-definition changes under the same ID are not fingerprinted;
authors must review acceptance when changing a rule's meaning. Identical-source
replacement cannot establish historical identity. Every edit to a source file,
including formatting, reopens its accepted findings.

JSON v2 records include a reason. Duplicate identities represent bounded
multiplicity: each record matches at most one finding, and unmatched surplus
records are stale. Both ordinary and CI complete checks fail stale entries without
writing. Add preserves existing records and reasons, prune removes only unmatched
records after complete analysis, and regen explicitly accepts the current eligible
findings. Regen may replace readable regular legacy/malformed files, but fails on
unreadable files, symlinks, and directories. Missing baselines may be created as
empty v2 documents. No-change incremental checks validate the baseline format
without making stale judgments.

Fresh full-vet build passed. The retained
`docs/milestones/7-baseline-probe` passed 189 CLI assertions, including unreadable
files, symlinks, unavailable compiler, no-change incremental validation, and the
adversarial identity/lifecycle cases above. The complete unit suite passed 37
tests at handoff. Numeric schema validation includes a tokenizer range check:
the supported Odin JSON parser itself can wrap oversized integer text before
converting it to the parsed numeric value, so checking the decoded version alone
does not reject `18446744073709551618`. Fractional and overflowing versions are
explicit regressions. These runs used private `/tmp` binaries; the root agent's
full CI remains the integration acceptance.
