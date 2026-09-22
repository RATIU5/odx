# Milestone 3 applicability research

Research only, before milestone 3 implementation. The complete roadmap was read.
Observed against a fresh build from the milestone 2 working tree, using
`/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`, version
`dev-2026-09-nightly:a2fb372`. Temporary probes used ordinary shell file writes and
Odin compilation; no Python or external parser was involved.

## Existing selection and the reproduced disagreement

`active_rules` in `odx/topics.odin` removes retired rules, rules outside selected
topics, and disabled identifiers. `role_applies` then includes every role when
`check.roles` is empty, otherwise exact listed strings, and excludes any
`check.except_roles` match. Exceptions win on overlap. Topic `applies_to.roles`
does not participate in enforcement or coverage.

`coverage_applies` additionally checks allocator mode and the existence of a
dependency policy for the package role. Runtime helpers implement those same
conditions separately. Compiler entity export currently begins for every package
when any entity rule is active, even when all such rules exclude that package.

`for` does the opposite: it selects whole topics by `applies_to.roles`, then emits
all their nonretired rules without considering selector roles or kind-specific
configuration. Global generated Markdown states topic roles as if they constrain
all rules. `explain` prints check kind, but no readable applicability contract.
README's statement that a no-role package gets no rule is false.

The reproducible temporary project had this compiler-valid source:

```odin
package example
state: int
Error :: enum { None, Failed }
operation :: proc() -> Error { return .Failed }
```

Its configuration assigned `package` the custom role `domain`, turned explicit
allocator checking off, and added topic `custom` with `applies_to.roles: ["edge"]`.
The custom rule prohibited mutable package declarations with
`check.roles: ["domain"]`.

| Invocation/input | Observed result before implementation |
| --- | --- |
| Full check, role `domain` | `custom/R1` and built-in `errors/R3` findings; complete evidence, exit 1. |
| `for package`, role `domain` | Only `package: role domain`; neither enforced rule is shown. |
| Global generated Markdown | Claims `custom/R1` applies to `edge`; lists allocator rule despite mode `off`. |
| Change package role to `edge`, then `for package` | Lists `custom/R1`, dependency import policy despite no dependency config, and `dependencies/R3` although it requires pure/service. |
| Same edge input, equivalent inline custom rule | Zero matches, proving the listed custom rule is inapplicable. |
| Remove roles entirely, full check | Built-in `errors/R3` still reports the unannotated procedure. |
| Same no-role input, `for package` | Prints no-role explanation and no rules. |
| No-role input, unrestricted mutable declaration trial | One match. |
| No-role input, `roles: [""]` trial | One match: empty string currently names unmapped packages. |
| No-role input, `except_roles: [""]` trial | Zero matches. |
| `explain custom --rule R999 --json` | Exit 0, entire topic including R1: JSON branch bypasses rule validation. |
| `explain not-a-topic --checklist` | Exit 0, empty output: checklist ignores unknown topic references. |

These are applicability failures, independent of whether the procedure error
heuristic or the mutable declaration selector is desirable. Their semantic
limits belong to the already recorded evidence boundaries and milestone 5.

## Recommended contract

Retain rule selectors as authoritative. Topic role metadata describes reviewer
advice and topic organization only. Never use it to suppress a mechanical rule
whose selector applies. This preserves enforcement and makes explanations match
it; intersecting topic and rule roles would silently stop currently active checks
in custom-role and no-role projects.

Use one applicability predicate with configuration, selector, and resolved role
for enforcement, coverage, path guidance, and compiler entity work selection:

1. Global availability is whole-topic override resolution, retirement, optional
   topic selection, and disabled rule identifiers.
2. Missing or empty inclusion list means all roles, including unmapped packages.
   Nonempty inclusion lists match exactly. Exclusions win over inclusions.
3. `vet_tag` additionally requires allocator mode `all`, or mode `pure` with
   package role `pure` or `service`. `off` is inapplicable.
4. `banned_import` additionally requires a dependency layer for the package role.
5. Other check kinds have no implicit role restrictions. `path_role` is how a
   project explicitly requires role assignment; missing roles alone are valid.

Unknown role strings in reusable rule selectors should remain permitted: a
project may load built-ins using only its own vocabulary, or maintain a policy
for a role with no package today. Package assignment overlap remains a project
configuration error, even for scoped checks. `default_role` must name a declared
role and is used only if no explicit glob matches. Multiple matching globs within
one role count once. An explicit empty role name should not be an undeclared
second configuration namespace; either preserve the existing empty-string
unmapped sentinel with documentation or explicitly reject it as a compatibility
change. The implementation decision must name that choice.

`for` should list exactly applicable enabled rules; reviewer advice may separately
follow topic role metadata. Disabled rules may remain visible in `explain` with
their reason, but must not read as active policy in path guidance. Path JSON must
filter rule arrays too, not merely change text. Global guidance should show
per-rule scope and configuration restrictions instead of a misleading topic-wide
scope. `explain --rule` must validate and select identically in text and JSON;
unknown checklist topics should fail explicitly. Reader advice is not evidence
of a successful check.

Keep inline trials raw and independent of permanent disabled identifiers,
suppression, or baselines: this is their existing declared purpose. The same
selector/configuration/package must have equal raw matching and applicability
when installed permanently. Trial status is not a substitute for project check
status.

## Alternatives and compatibility

Making topic scope an inherited selector is superficially simple but changes
existing enforcement and adds ambiguous precedence when a rule chooses a broader
scope. Restricting all packages to the built-in role vocabulary would contradict
the project-policy goal. Removing topic role metadata entirely loses useful
reader-advice scope. Keeping rule scope authoritative and labeling topic advice
is the smallest compatible correction.

No new selector language, parser, or cache is needed. Shared applicability adds
negligible cost and can avoid unnecessary compiler doc processes. The cost is a
small API and a deterministic explanation of conditional scope. Freshness checks
and ownership of generated Markdown remain milestone 4 work.

Acceptance should cover positive custom-role matches, false topic scope,
inclusion/exclusion overlap, empty roles, default roles, disabled rules, missing
dependency layers, allocator modes off/all, text/JSON/trial parity, and unknown
references. An adversarial test must put an active rule in a topic whose metadata
excludes the package, plus an inactive rule in a topic whose metadata includes
it; topic-only filtering fails both. Research probes establish the present
failure and desired boundary, not implementation acceptance or cross-platform
validation.
