# Milestone 3: selector contracts and applicability

Implemented with `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09`,
Odin `dev-2026-09-nightly:a2fb372`, on macOS arm64. All three investigations
finished before implementation: [selectors](3-selector-research.md),
[applicability](3-applicability-research.md), and
[authoring](3-authoring-research.md). Installed core JSON, AST, parser, and
strconv sources were the implementation references. No second parser was added.

## Problem and decision

A procedure selector with `name:"target"` matched every procedure because that
field was accepted but unused. Negative indices, nested misspellings, and null
booleans likewise produced unintended policies. Guidance used topic role
metadata while execution used rule roles, hiding enforced rules and listing
inapplicable ones. File trials bypassed permanent-rule validation; unknown rule
tests could succeed without testing anything.

Retain the small selector vocabulary and validate exactly the fields each
selector consumes. Keep rule filters authoritative and share applicability
between execution, coverage, and guidance. Retain whole-topic replacement and
explicitly distinguish raw trials from configured project checks.

| Alternative | Benefit | Cost and decision |
| --- | --- | --- |
| Existing field bag with strict discriminator validation | Preserves public syntax and matchers; small correction | Requires explicit field tables and presence checks; selected |
| Separate typed unions for each selector | Stronger internal representation | JSON discriminator dispatch still needs custom validation; defer until vocabulary growth warrants it |
| General structural templates or scripts | Broader potential policies | New syntax, execution, distribution, and evidence contracts; does not cheaply repair current bugs |
| Inherit topic roles into every rule | Simple apparent hierarchy | Silently disables existing custom/no-role checks; rejected |
| Merge individual rules from local and built-in topics | Less copying | Needs deletion, metadata inheritance, and future-upstream precedence; whole-topic replacement remains simpler |

## Executable selector reference

All selectors require `kind`. All accept optional `roles` and `except_roles`
arrays. Fields not listed for that selector are errors even when their value is
false, null, empty, or otherwise seemingly harmless. Unknown nested fields,
null primitive values, and empty required strings fail before source checking.

| Kind / matcher | Additional accepted fields | Meaning and defaults |
| --- | --- | --- |
| `path_role` | None | Reports selected package directories with no assigned/default role. Roles are otherwise optional. |
| `vet_tag` | None | Requires the existing explicit-allocator file tag, subject to `odin.explicit_allocators`. No allocator behavior proof. |
| `banned_import` | `from` | Reads the package role's dependency layer. Omit `from` or use exactly `"dependencies.may_import"`; it is a compatibility alias, not configurable indirection. See milestone 2 for graph semantics. |
| `require_attribute` | Required `attribute`; optional `on` | `on` absent or `"exported_procs"` means compiler-exported non-test procedures whose final result is classified as an error. Reports absence of the named attribute. It is not an attribute requirement on every procedure. |
| `pattern`, `match:"call"` | `name`, `names` | At least one nonempty spelling. Exact union of both fields, deduplicated. Recursive syntactic call matching with file-import alias normalization. No glob or resolved-callee semantics. |
| `pattern`, `match:"import"` | Required `name` | Direct file-level ordinary imports. Decoded path matches exactly, or by prefix when `name` ends in `*`. Plural `names` is unsupported. |
| `pattern`, `match:"proc"` | `exported`, `requires_param` | Direct file-level procedure literals. `exported:true` excludes syntactically private declarations; absent/false includes both. No `name` filter is implemented: supplying one now fails. |
| `pattern`, `match:"decl"` | Required `at:"package_scope"`; optional `mutable` | Direct file-level value declarations. `mutable:true` selects mutable declarations; absent/false includes mutable and immutable declarations. |
| `pattern`, `match:"foreign"` | None | Direct file-level foreign imports and foreign blocks. No transitive, conditional-block, or runtime foreign-access claim. |

`requires_param` is an object with required nonempty `type_suffix` and optional
`index` (default zero). Its only other accepted key is that index. It reports a
procedure whose parameter is absent or does not have the requested syntactic
type suffix. Indices count individual names: `a, b: int` occupies two positions.
An index beyond the signature is a legitimate violation. Negative, fractional,
null, nonfinite, and overflowing indices are errors. Pointer layers are peeled
and the last type identifier is tested; aliases and inferred/default parameter
types are not semantically resolved. It is a requirement, not a positive
parameter filter.

The reference JSON decoder and integer conversion can wrap oversized decimal
and hexadecimal integers. Policy loading now checks integer token magnitudes
before decoding and restricts integer literals to signed 64-bit range. Selector
indices additionally must fit the host `int`. This also prevents policy integers
such as configuration versions from wrapping into valid-looking values. Native
JSON duplicate-key rejection remains in use.

## Scope and precedence

1. Load built-in topics, then local `.odx/topics/<name>`. A local topic with the
   same name replaces the entire built-in topic, including metadata and rules;
   there is no rule merge. Topic and rule order is deterministic.
2. Retired definitions are inactive records. Active definitions are validated
   even when project-disabled. Historical retired definitions may retain old
   check shapes; they cannot be trialed/tested as active rules, and reactivation
   requires current validation. Duplicate IDs and filename/ID disagreement fail.
3. Resolve disabled IDs against the resulting rulebook. Unknown references,
   including IDs removed by a local replacement, fail. Normal checks omit
   disabled rules; definitions remain available to explanation and explicit tests.
4. Apply selected topics, then each rule's `roles` and `except_roles`. Missing
   or empty inclusion means all roles, including unmapped packages. Strings match
   exactly. `""` explicitly means unmapped in selector arrays. Exclusion wins
   when the same role appears in both lists. Reusable selectors may name roles
   not declared in this project; such roles simply do not match.
5. `vet_tag` additionally requires allocator mode `all`, or mode `pure` and role
   `pure`/`service`; mode `off` is inapplicable. `banned_import` additionally
   requires a dependency layer for the resolved role. Other kinds have no hidden
   role gate. Entity export is omitted for packages with no applicable entity rule.

Configured role names must be nonempty. Explicit role-glob overlaps are project
errors; multiple matching globs of one role count once. `default_role` applies
only when no explicit role matches and must name a declared role. With neither,
the package is unmapped. Rule metadata `role` is the example-test role (default
`edge`), not an enforcement filter.

Topic `applies_to.roles` scopes reviewer advice, not mechanical rules. This
preserves enforcement while repairing descriptions. Its nested keys and value
types are validated too. A rule in a topic whose advice excludes `domain` can
still apply to `domain` through its own selector.

## Commands and compatibility

- `for <path>` uses canonical package selection and requires exactly one
  included package. Its text, JSON, and emitted Markdown contain applicable
  enabled rules only. A directory selecting several packages now fails rather
  than guessing a role for a nonexistent aggregate package.
- Global emitted Markdown selects rules applicable to at least one discovered
  package. An empty project gets an explicitly conditional catalog. Individual
  rule scope and reviewer-advice scope are labeled separately.
- `explain` remains a definition catalog, including disabled active definitions
  with their reasons. Text and JSON `--rule` select the same active definition;
  unknown/retired targets fail. Unknown checklist topics and incompatible rule
  selection options fail too. JSON rule descriptions gain `scope` and
  `disabled_reason`; catalog listing can still expose retired records.
- Inline `rule try` validates a selector. `rule try --file` additionally uses
  permanent-rule metadata validation and rejects retirement. Draft filenames
  need not equal the eventual installed ID. Both use the same applicability and
  matcher as permanent rules. Raw trials intentionally bypass permanent disabled
  IDs, ignores, and baselines; matching is not a project-cleanliness verdict.
- `rule test` resolves its target first. Unknown or retired rules exit 2 instead
  of succeeding without work. Active disabled definitions remain testable.
  Example tests use their synthetic configuration and effective rulebook.
- All five public matchers remain. Previously ignored fields now fail rather
  than acquiring speculative semantics. Explicit empty `from`/`on` must be
  omitted or replaced with their supported constants. False narrowing flags
  retain their established “all” meaning.

Generation does not add automatic freshness checking or change `fix_hint`.
Those remain milestone 4 work. Syntactic traversal expansion, allocator/error
heuristic redesign, and exhaustive strict-policy examples remain later work.

## Acceptance and limits

The retained [Odin CLI probe](3-probe/main.odin) exercises the ignored-name
counterexample, every public matcher, invalid field presence including false
and null, nested misspellings, decimal/hexadecimal overflow, default/grouped
parameter indices, trial/permanent match-location parity, disabled and retired
definitions, whole-topic replacement, duplicate identifiers, custom/unmapped
roles, role overlap/defaults, kind-specific gates, and all guidance formats.

Positive and negative policy examples include a small mutable-state restriction
that accepts constants and procedure-local state, direct foreign syntax, and a
stricter role-selected subset that leaves an unmapped package outside its scope.
Probe source is compiled where validity matters. These demonstrate existing
expressiveness without a new DSL; they do not claim the entire strict roadmap
use case, resolved calls, ownership, purity, or independent-project adoption.

The implementation adds small policy-input validation passes and a shared
applicability predicate; it avoids compiler doc work for inapplicable packages.
No cache or dependency was added. Other host platforms, extremely large policy books, and
external authoring usability remain unproven. Revisit typed-union internals or
topic inheritance only when concrete policy growth justifies their complexity.

Final `mise run --force ci` passed: 25 unit tests with address sanitization and
memory tracking; 121 milestone 3 CLI assertions; 113 milestone 2 assertions;
49 milestone 1 assertions; all five fixture projects; rule and reader blocks;
four exemplar packages; and the compiler redundancy audit. The self-check
reported 43 files in five packages with complete evidence and no findings.
Doctor retained its two existing warnings about hook configuration and unused
allocator-advice roles. Generated `CLAUDE.md` was refreshed with the new scope
selection. `git diff --check` passed; `ROADMAP.md` remains ignored and untracked.
