# Milestone 3 authoring research

Research completed before implementation on 2026-09-21. The whole roadmap was
reviewed. This record concerns authoring, replacement, and trial contracts;
selector and applicability research are recorded separately.

## Evidence

The reference compiler is
`/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`, reporting
`dev-2026-09-nightly:a2fb372`. The existing `build/odx` was exercised against a
temporary project containing one `domain` package:

```odin
package sample
Ctx :: struct {}
alpha :: proc(ctx: ^Ctx) {}
beta :: proc() {}
```

`odin check <sample> -no-entry-point` succeeded. The following are observed
pre-change `rule try --count` results, all exiting zero:

| Check | Result and implication |
| --- | --- |
| `pattern/proc`, `name:"alpha"` | Two matches: the accepted name filter is ignored. |
| `pattern/proc`, `requires_param:{index:-1,type_suffix:"Ctx"}` | Two matches: impossible negative index silently becomes an all-procedure prohibition. |
| `pattern/proc`, `requires_param:{type_suffix:"Ctx",typo:1}` | One match: omitted index defaults to zero; nested unknown key is ignored. |
| `pattern/proc`, `roles:["domain"],except_roles:["domain"]` | Zero matches: exclusion wins, but the contradictory input is accepted. |
| `banned_import`, `from:"typo"` | Zero matches: arbitrary `from` is accepted and never consumed. |
| `pattern/call`, `names:[""]` | Zero matches: empty call spelling is accepted. |

A drafted file containing only `id:"R90"`, `severity:"erorr"`, and a valid
`pattern/proc` check produced two trial matches. Installing the identical file
under `.odx/topics/errors/` rejected the invalid severity and missing statement,
why, instead_of, evidence, and cost. Both paths call the same selector validator
and matcher, but `--file` bypasses permanent-rule metadata validation.

A `retired:true` drafted file with `pattern/proc` likewise produced two trial
matches; the installed rule was excluded from normal checks. Both
`rule test errors/R999` (unknown) and `rule test errors/R91` (retired) exited zero
without testing any block. These are false-success authoring workflows.

Installing a valid `errors/R90` under a local `errors` topic replaced the entire
built-in errors topic. `explain errors --json` contained R90 alone and
`overrides:true`. Its topic declared `applies_to.roles:["unrelated"]`, but its
unrestricted procedure rule still reported both procedures in role `domain`.
`for <sample> --json` returned no topics. Topic metadata currently filters
instructions, while rule selectors filter enforcement.

Source inspection establishes the following additional behavior:

- Local topic directories and rule filenames are sorted; the final topic list is
  sorted. Replacement is by topic name and does not merge rules or metadata.
- Rule IDs must start with `R` and equal the filename stem. Duplicate IDs are
  diagnosed inside each topic; identical IDs across topics are distinct.
- `validate_project` resolves disabled IDs against the effective rulebook after
  replacement. A disabled reference to an omitted built-in rule becomes unknown
  and fails instead of silently disabling something else.
- Disabled rules require reasons but still undergo loading and selector
  validation. Retired rules skip `validate_rule` entirely, preserving historical
  records with obsolete check shapes.
- Topic directory/name disagreement already fails. Unknown top-level rule and
  check keys fail. Nested `requires_param` keys are not validated.
- `role` is the rule-block test role, defaulting to `edge`; it does not constrain
  a rule's runtime scope. `check.roles` and `check.except_roles` do.
- Native JSON parsing rejects duplicate object keys: a trial with duplicate
  `kind` fields reported `Duplicate_Object_Key`. The reference implementation in
  `core/encoding/json/parser.odin` checks object-key presence before insertion;
  no replacement JSON parser is needed.
- Rule-block tests run the effective rulebook under a synthetic configuration,
  not the project's disabled set. That is appropriate for validating definitions
  separately from adoption configuration, but needs an explicit contract.

## Alternatives and recommendation

Retain whole-topic replacement. It is deterministic and permits a project to
remove built-in opinions deliberately. Rule-by-rule inheritance would save
copying but needs delete semantics, metadata precedence, and compatibility with
future upstream rules; those costs are not justified by current requirements.
Document replacement and continue validating disabled references afterward.

Retain the small typed selector vocabulary with strict per-kind and per-matcher
field validation. It already supports a minimal custom syntactic-call policy and
a stricter custom-role policy combining mutable declarations, foreign syntax,
procedure parameter conventions, and import boundaries. Adding a structural
pattern language or executable plugins would broaden potential policies but
adds distribution, interpretation, and diagnostics obligations without solving
the demonstrated ignored-field failures. These examples establish syntactic
expressiveness, not allocator effects, resolved call identity, or ownership.

Share permanent-rule validation with `rule try --file`; inline `rule try` remains
a lightweight selector-only workflow. Reject retired file trials explicitly
instead of running a rule permanent checks exclude. Resolve `rule test` IDs
before iteration and reject unknown or retired targets explicitly. Active but
project-disabled definitions should remain testable because this command checks
their examples independently of project adoption choices.

For `banned_import.from`, either remove the field with migration guidance or
accept only the existing literal `dependencies.may_import` as a compatibility
alias for the built-in configuration source. Arbitrary values must fail. The
second option preserves existing files without introducing indirection.

Retired definitions may retain their historical syntax because they are not
accepted executable selectors. Make their inactive state explicit in discovery;
do not report them as successfully tested. Validate any active rule even when
disabled, so disabling cannot conceal a malformed policy awaiting activation.

## Acceptance probes for implementation

1. Use the compiler-valid two-procedure example above: irrelevant `name` on a
   procedure selector, negative indices, nested typos, and empty spellings fail
   before scanning. An omitted parameter index means zero if that compatibility
   default is retained; grouped parameter names still count individually.
2. Compare inline trial, valid-file trial, and installed rule findings under an
   unfamiliar role and under no assigned role. Match locations and subjects,
   not just aggregate counts. Disabled rules are omitted only by normal scans;
   explicit trials intentionally test their selector.
3. Show invalid severity and missing metadata reject both valid-file trial and
   permanent installation. Unknown and retired `rule test` targets, plus retired
   file trials, fail explicitly.
4. Replace a built-in topic with one local rule; prove omitted upstream rules
   remain absent, unrelated topics survive, and disabled references to removed
   rules fail. Duplicate IDs and filename mismatches remain errors.
5. Check the same custom rule through enforcement, coverage, `for`, and generated
   guidance despite unrelated topic role metadata. Preserve reader metadata
   separately from executable applicability.
6. Demonstrate positive, negative, and boundary examples for a tiny local call
   restriction and stricter role-restricted structural policies. Do not expand
   traversal or behavioral claims as a side effect of validation changes.

These checks require no cache or parser dependency. Validation costs scale with
the small policy input, not source size. Revisit topic inheritance or a richer
language only when a concrete independent policy cannot be expressed reasonably.
This research did not measure external authoring usability, other operating
systems, or policies requiring semantic call resolution. Implementation and
acceptance results belong in the milestone decision record.
