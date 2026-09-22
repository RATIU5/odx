# Strict application policy

This synthetic application selects five project-owned restrictions for its
`domain` role. Its `adapters` and `app` roles allow process state and OS access.
Copy this directory into a new project and adjust its role paths, local rules,
and dependency lists. It uses the existing policy language without a preset or
engine modification. These are this application's choices, not universal Odin
requirements or a mechanical implementation of TigerStyle.

From the odx repository root, using a freshly built binary and the supported
`dev-2026-09` Odin compiler:

```sh
build/odx check --root examples/policies/strict --ci --json
build/odx rule test dependencies/R2 --root examples/policies/strict
build/odx rule test dependencies/R3 --root examples/policies/strict
build/odx rule test dependencies/R4 --root examples/policies/strict
build/odx rule test errors/R3 --root examples/policies/strict
build/odx rule test allocators/R1 --root examples/policies/strict
build/odx guidance write AGENTS.md --root examples/policies/strict
build/odx guidance check AGENTS.md --root examples/policies/strict
odin check examples/policies/strict/domain -no-entry-point
odin check examples/policies/strict/adapters -no-entry-point
odin check examples/policies/strict/app
```

The project passes as supplied. `cases/*.odin.txt` are excluded source variants,
not discovered Odin packages. Copy one into `domain/case.odin` in a temporary
copy to exercise the corresponding failure, then remove it before the next case.
`adapter-counterexamples.odin.txt` belongs in `adapters/case.odin` instead.

| Rule | Violating case | Compliant / false-positive counterexample | Boundary |
| --- | --- | --- | --- |
| `dependencies/R2` | `transitive.odin.txt` imports an allowed adapter that reaches `core:os` | The passing adapter itself may import OS; domain receives state from a caller | Included project source is followed; built-in collections are opaque. This does not prove no runtime I/O. Full and scoped domain checks must agree. |
| `dependencies/R3` | `mutable.odin.txt` declares package state | Struct fields, local variables, constants, and mutable state in app/adapters are allowed | Conditional branches and foreign containers count; imported state and mutable data behind constants remain possible. No purity claim. |
| `dependencies/R4` | `foreign.odin.txt` declares a foreign import | Foreign-looking strings are allowed; direct foreign syntax in adapters is allowed | Foreign blocks are also selected; imported code may use FFI. No transitive foreign-access guarantee. |
| `errors/R3` | `error.odin.txt` omits the attribute on a selected final-result API | Both selected failure types are attributed; predicates, lookup bools, status enums, optional unions, and private APIs are allowed without it | Canonical name suffixes can collide. Aliases use canonical names; non-final and anonymous results are outside scope. Explicit `_` discard is allowed. |
| `allocators/R1` | `allocator.odin.txt` omits the leading directive | Passing domain files have it; app/adapters omit it | Tag presence is the source check; the compiler vets affected calls. Scratch/indirect allocations remain possible and context replacement is no exemption. |

`counterexamples.odin.txt` is a passing domain variant combining the counterexamples
above. `adapter-counterexamples.odin.txt` combines mutable state, foreign syntax,
an unannotated failure result, and no allocator tag outside the opted-in role.
Both must remain clean. The committed integration probe compiles valid variants
and asserts exact findings, scoped results, and guidance freshness.

Local topic directories replace all three same-name built-in topics, including
their prose. Rule scope is explicit; path-specific app guidance should contain
none of the five domain rules. The domain dependency policy permits the adapter
role directly to demonstrate that transitive deny still applies to an allowed
intermediate package. Production project authors can narrow this allow list.

`errors.structural: false` selects only the configured `Domain_Failure` and
`Storage_Failure` canonical suffixes. A named status enum with `Ok` or an optional
union therefore does not become an error API merely because of its shape.
`odin.explicit_allocators: "all"` enables custom roles; the local allocator rule's
`roles: ["domain"]` filter chooses which files must carry the tag. Compiler flags
are explicitly empty here so compilation and formatting choices remain separate
from the five demonstrated contracts.

The default file-tag audits remain enabled across all roles: feature directives
need reasons and vet disables need allow-list entries. These separate settings
appear in the effective configuration; `odin.audit_file_tags: false` opts out.

Generated guidance labels ownership and error-handling questions as reviewer
advice. Neither a directive, attribute, defer statement, nor assertion count
proves correct ownership, useful recovery, allocation freedom, or cleanup on all
paths. This fixture establishes deterministic policy behavior, not external
adoption value or agent productivity.
