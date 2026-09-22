# Milestone 5 allocator research

Research completed against `/opt/homebrew/bin/odin version dev-2026-09:a2fb372b7`
on Darwin arm64, the version selected in `mise.toml`. No implementation changes
were made during this research.

## Authority and scope

The official [Odin overview](https://odin-lang.org/docs/overview/#implicit-context-system)
describes implicit context as an interception mechanism, including replacement of
allocators in called code. Its allocator section explains that dynamic arrays and
maps store allocators and that temporary allocation is reclaimed by an explicit
reset such as `free_all(context.temp_allocator)`. Its
[file-tag documentation](https://odin-lang.org/docs/overview/#vet) identifies
`explicit-allocators` as a per-file vet option. These facts support legitimate
implicit-context designs, not a universal requirement for allocator parameters.

Version-matched primary runtime sources were read locally:

- `core/fmt/fmt.odin:230`: `tprintf` constructs a builder with
  `context.temp_allocator` and has no allocator parameter.
- `base/runtime/core_builtin.odin:731`: append grows through the array reserve
  implementation; the append API does not accept an allocator argument.
- `base/runtime/core_builtin.odin:1389`: reserve initializes an absent stored
  allocator from context.

These paths are relative to `/opt/homebrew/Cellar/odin/2026-09/libexec`.
Attempted web reads of the compiler revision's C++ source failed with cache
misses; no claim here depends on having read that source. Executed compiler
probes and shipped runtime implementation establish the narrower observations.

## Compiler counterexamples

Each case was a fresh `.odin` file with `package probe`, checked with
`odin check <file> -file -no-entry-point -vet`. Unless indicated otherwise, it
started with `#+vet explicit-allocators`. Sources remain in the session's
`/tmp/odx-m5-allocator-0kvf7g6i` directory; the table preserves reproducible bodies.

| Case | Procedure body or declaration | Compiler result |
| --- | --- | --- |
| Untagged implicit make | `f :: proc() { a := make([dynamic]int); delete(a) }` | Accepted under `-vet` |
| Tagged implicit make | Same source with tag | Rejected: allocator must be explicitly provided |
| Explicit make then append | `f :: proc() { a := make([dynamic]int, context.allocator); append(&a, 1); delete(a) }` | Accepted |
| Append on zero dynamic array | `f :: proc() { a: [dynamic]int; append(&a, 1); delete(a) }` | Accepted |
| Explicit scratch allocation | `f :: proc() { a := make([]int, 1, context.temp_allocator); _ = a }` | Accepted |
| Deliberate context replacement | `f :: proc() { context.allocator = context.temp_allocator; a := make([dynamic]int); delete(a) }` | Rejected: allocator must be explicitly provided |
| Default allocator parameter declaration | `f :: proc(allocator := context.allocator) { a := make([dynamic]int, allocator); delete(a) }` | Accepted |
| Call omitting default allocator | `f :: proc(allocator := context.allocator) {}; g :: proc() { f() }` (separate declarations on separate lines) | Rejected at `f()` |
| Hidden scratch API | `import "core:fmt"` then `f :: proc() { s := fmt.tprintf("%d", 1); _ = s }` | Accepted |
| Header comment before directive | `// license` before tag, then `f :: proc() {}` | Accepted |

These are compile checks, not runtime memory-safety proofs. The zero-array append
and `fmt.tprintf` cases directly refute claims that every allocation in a tagged
file names an allocator. Explicit `context.allocator` also remains a legitimate
argument: the tag does not require an arena, lifetime, or signature policy.

## odx behavior and documentation audit

`check_explicit_allocators` in `odx/checks.odin` checks parsed file vet tag names
for the positive `explicit-allocators` token. It does not inspect allocation calls,
scratch use, or context assignments. `check_applies` adds the configured
`odin.explicit_allocators` mode to rule roles: `pure` means pure/service, `all`
extends applicability, and `off` disables the check.

A temporary CLI project with `{version:1,roles:{pure:["pure"]},odin:{flags:[]}}`
and `pure/main.odin` verified the following using
`build/odx check --root <project> --json`:

| Source | Result |
| --- | --- |
| Untagged explicit scratch allocation | One `allocators/R1`; exit 1 |
| Untagged file replacing context allocator | One `allocators/R1`; exit 1 |
| Same replacement with `// odx:ignore-file allocators/R1 reason: context boundary intentionally inherits allocation` | Suppressed; exit 0 |
| License comment before valid tag | No `allocators/R1`; exit 0 |

Temporary project: `/tmp/odx-m5-allocator-policy-6u5cbpqq`.

Required corrections:

- R1 statement's "starts with" overstates source position. Require the directive
  before the package declaration; leading comments are valid.
- R1 rationale falsely promises automatic scratch and context-replacement
  exemptions. No such inference exists. Document explicit project exceptions.
- R1 cost falsely says every make/new/append names an allocator. Append is a
  concrete counterexample. Limit cost to affected calls with allocator defaults.
- Topic summary and introduction conflate tag presence, signatures, allocation
  flow, and lifetime. Separate compiler behavior from project review advice.
- "Outside any static checker's reach" is unsupported. Say odx does not establish
  allocator lifetime or ownership.
- The reader checklist can recommend allocator parameters for caller-owned
  output, with owned containers, scratch work, and context interception as valid
  alternatives whose lifetime contracts need review. It should not universally
  require the parameter to be last.
- Scratch lifetime is until the allocator is reset or otherwise invalidates
  storage, which can happen before the next frame/request. Document that actual
  boundary and ensure scratch data does not escape it.
- Remove references to an active allocator R2: that reader convention is not a
  firing rule. Compilation of reader snippets establishes language validity only.
- Sanitizer configuration detection by doctor is not a runtime memory-safety
  guarantee; describe configured flags and tested execution separately.

## Recommended contract and alternatives

Suggested machine statement: "Files selected by this rule must contain
`#+vet explicit-allocators` before the package declaration." Suggested rationale:
"This project opts selected files into the compiler's explicit-allocator vet
check. odx verifies the tag; compiler diagnostics enforce affected call sites.
Neither establishes allocation flow, ownership, or lifetime."

Suggested reader heading: "Review allocation ownership and choose explicit
parameters or documented context/container allocation deliberately."

| Approach | Benefit | Limitation |
| --- | --- | --- |
| Keep R1 a required tag and document reasoned file ignores/role opt-outs | Matches existing implementation; no invented semantics | Project exceptions need explicit configuration or annotation |
| Infer exceptions from context assignments or scratch names | Less annotation | An assignment does not establish a file's purpose, lifetime, or all call behavior; easy evasion |
| Enforce an allocator signature syntactically | Clear project-specific convention if independently desired | Does not prove the parameter is used or capture allocation through owned containers |
| Review lifetime and interception contracts manually | Can account for API intent and ownership | Not a mechanically proved guarantee |

Recommend the first and fourth approaches for this milestone. They correct
overclaims without introducing an effect-analysis feature.

## Implementation acceptance tests

Retain persistent compiler cases for omitted/default allocator calls, explicit
scratch, context replacement rejection, zero-array append, and hidden scratch
allocation. Assert diagnostic content as well as failure for rejected examples.
Add CLI cases demonstrating no inferred scratch/context exemptions, a reasoned
file ignore, and a valid tag after a header comment. Verify generated explain,
checklist, guidance and diagnostic metadata contain the corrected scope; refresh
managed guidance because embedded prose contributes to the policy snapshot.
