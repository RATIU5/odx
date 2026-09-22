# odx

The [existing-policy semantics contract](docs/milestones/5-existing-policy-semantics.md)
records allocator, declaration, and error-classification boundaries and compiler proofs.

The [rule contract](docs/milestones/3-rule-contracts.md) defines accepted selector
fields, role scope, overrides, and trial behavior.

See the [architecture and incremental contract](docs/milestones/2-architecture-and-incremental.md)
for milestone 2 decisions, graph boundaries, and validation.

The [analysis and coverage contract](docs/milestones/1-analysis-and-coverage.md)
defines what each check establishes. Dependency checks load the project source
graph even when findings are scoped to selected files or packages. Rule selection
agrees across checking and generated guidance. Managed guidance supports freshness
checks, and repair hints describe the desired correction.

odx is a secondary vet pass for Odin: it checks that every guarantee the compiler offers is
switched on, and enforces the few conventions a project has explicitly agreed on, with a
reason for every rule and an escape hatch for every reason. Agents and CI call it the same
way; it never calls a model and never blocks anything.

It does not make code good. What it cannot do:

- verify an allocator matches its intended lifetime; only that the `#+vet` tag is present.
- see allocator flow at all; the implicit context exists so callers can intercept it.
- judge taste. Naming, formatting and brace style are never built in.
- make an agent write better Odin by sitting in its loop. That was measured (below) and
  the numbers went the wrong way, so the loop is gone.

## Guarantees

The compiler cannot check which flags you passed it, and `#+vet explicit-allocators` is a
per-file tag with no global switch. `odx doctor` lists every guarantee the installed compiler
offers, whether `odin.flags` in `odx.json5` turns it on, which files opt out via `#+vet !x` or
`#+feature`, and how many pure/service files carry the allocator tag. It warns when the
compiler gained a flag the project has not adopted, so the set ratchets as Odin grows. A flag
considered and refused goes in `odin.declined: { "-vet-style": "why" }`, so _considered_ and
_not yet seen_ stay distinct. `odin.tagged_files_min` is a floor on allocator-tag coverage:
doctor errors below it and asks you to raise it as coverage grows. `odx doctor --json` returns
`{schema, errors, warnings, guarantees: {flags: [{flag, on, declined}], tagged, needed}}`.

`odx check` enforces the per-file half: a missing allocator tag is `allocators/R1`, a
`#+feature` opt-out without a `// reason: <why>` on its line is `odx/feature-optout`, a
`#+vet !x` not listed in `odin.allowed_vet_disables` is `odx/vet-disable`.

## Rules

Four rules, all mechanical, all counting:

| rule              | what                                                                                                                  | how                                  |
| ----------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `allocators/R1`   | selected files contain `#+vet explicit-allocators` before the package declaration | file tag |
| `dependencies/R2` | ordinary imports obey `may_import` and `deny`, including denied imports reached through project production source | native AST and project source graph |
| `dependencies/R3` | no mutable package-level variables in pure/service packages                                                           | AST                                  |
| `errors/R3`       | exported non-test procedures whose named final result matches project error classification carry `@(require_results)` | compiler entity table (`odin doc`) |

Roles are opt-in: `odx.json5` assigns `pure`, `service` or `edge` per package directory and
says who may import whom. Unrestricted rules also apply to packages without a role;
`check.roles: [""]` explicitly selects those packages. `errors/R3` classifies a
canonical named final-result type by a suffix in `errors.types` (default
`["Error"]`), or, with `errors.structural: true` (the compatibility default), an
underlying enum with `None`/`Ok` or a union admitting `nil`. This is a project
heuristic: optional/status values can match without representing failures.
Set `errors.structural: false` for suffix-only classification; combine it with
`types: []` to classify nothing. Aliases use the compiler's canonical name;
distinct types retain their own name. Anonymous results are outside this check.

`@(require_results)` rejects a bare call to an attributed procedure, but permits
`_ = f()` and `x, _ := g()`. It does not prove callers inspect, handle, or propagate
failures. Predicates, lookup success flags, several error domains per package,
and either explicit branches or `or_return` are legitimate design choices.

Allocator R1 verifies the directive only. Scratch allocation and deliberate
context replacement have no inferred exemption; use role configuration, disabling,
or a reasoned suppression for a project exception. The compiler's tag checks
affected allocator defaults, not all allocation, ownership, or lifetime.

Mutable declaration checks include package `when` branches (even inactive ones),
foreign-block variables, and thread-local declarations. They stop before procedure
bodies and report grouped variables once. This restriction does not prove purity.

Each rule is one file, `rules/<topic>/<id>.odx.md`: JSON5 frontmatter (`key: "value",` per
line) with `statement`, `why`, `instead_of`, `evidence`, `cost`, `severity` and `check`, then
three fenced blocks. ` ```odin prelude ` is a sibling file of shared types, ` ```odin fires `
must produce that rule and no other finding, ` ```odin silent ` must compile and produce
nothing. `odx self-test` compiles every block, so the doc, the exemplar and the test are one
artifact. Conventions only a reader can enforce live in `rules/<topic>/topic.md` under
`## Reader checks`, with the same fires/silent pairs, compiled the same way and printed by
`odx explain --checklist`. A project adds `.odx/topics/<name>/` in the same format.

Adding a rule is a text edit. `check: { kind: "pattern", match: <class>, ... }` selects an
AST node class (`call`, `import`, `proc`, `decl`, `foreign`) and filters it: `name`/`names`
for calls, singular `name` for an import glob, `exported` and `requires_param: { index, type_suffix }` for
procedures, `at: "package_scope", mutable: true` for declarations, plus `roles`/`except_roles`.
`odx rule try '<check json5>' [paths]` prints every match before any file exists,
`odx rule add <topic>` scaffolds the next id, `odx rule test <topic>/<id>` compiles its
blocks. The evidence bar is the one `allocators/R1` and `errors/R3` meet: a compiler version
and a command whose output shows the failure. Anything less stays a reader check.

Optional rule frontmatter `fix_hint` gives a nonempty desired correction. If absent,
the rule statement is the compatibility fallback. Keep rationale in `why` and the
discouraged alternative in `instead_of`; hints are guidance, not automatic edits.

## Commands

```
odx check [<path>...] [--json] [--since <ref>] [--fast] [--ci]   exit 1 on violations
odx doctor [--ci] [--json]        guarantees, toolchain, config, mise.toml drift
odx for <path> [--brief]          the rules that apply to a file or package
odx for --emit-md [<path>]       portable managed Markdown (--emit-claude-md alias)
odx guidance check|write <markdown-file> [<package-path>]  verify or regenerate guidance
odx explain [<topic>] [--rule R3] rules, rationale, fires/silent
odx explain --checklist           the reader checks, for a reviewer
odx ignores [--stale]             every odx:ignore; --stale: suppressing nothing
odx baseline add | regen          freeze current violations by semantic key
odx hook edit                     Claude Code PostToolBatch hook: report, exit 0
odx init [--hooks]                write odx.json5 and mise.toml (--hooks: hook + CLAUDE.md)
odx self-test                     fixtures and every rule block
odx rule try | add | test         draft, scaffold, test a rule
```

Check exit codes are contract: `0` no unbaselined errors (warnings also fail with
`--strict`), `1` failing findings, `2` tool or config error. Coverage must be inspected
separately: partial scans can exit 0. `hook edit` always exits 0.
`--json` on `check` is the machine contract, `schema: 1`. Each violation carries `file`, `line`, `col`, `rule`, `severity`,
`check`, `message`, `class`, `subject` (the baseline key), `baselined`, `ignorable`,
`statement`, `why`, `fires`, `silent`, `fix_hint` (the desired repair) and
`ignore_syntax` (the exact suppression comment), plus `blocking`, always true, kept for the
schema, not an exit-status decision. Milestone 4 corrects the formerly inverted
`fix_hint` value without changing its string type or schema number; consumers that
used it as discouraged behavior must use the additive `instead_of` field.
Additive `evidence` and `boundary` describe the check's evidence source and limits.
Compiler/internal notes leave policy repair metadata empty.
`summary` carries `errors`, `warnings`, `ignored`, `files`, `baselined` and
`omitted`.

`coverage` records selected packages/files, compiler flags, and each check's
evidence, boundary, status, reason, and raw finding count. Source checks include
inactive/platform/generated/test files; compiler checks use the selected target
and do not execute tests. `coverage.complete` describes completed evidence within
those boundaries, not absence of violations or whole-project compliance.
`--fast` and empty `--since` selections report incomplete coverage. Missing or
unsupported required evidence exits 2. Failed analysis cannot shrink or regenerate
a baseline. See the linked contract for exact limits and statuses.

For architecture checks, `may_import` matches a direct ordinary import's target
role or its path (an exact string, or a prefix ending in `*`). `deny` also follows
ordinary imports through included project packages, even packages without roles.
The selected package's own test imports are checked; transitive traversal excludes
dependencies' `*_test.odin` files. Built-in `base:`, `core:`, and `vendor:` packages
are opaque leaves: their direct import names are checked, but their dependencies
are outside this graph. Required excluded, missing, unknown-collection, or
outside-project edges are unsupported evidence. This policy establishes neither
foreign-access freedom nor runtime purity. Foreign imports and foreign blocks are
separate syntax and are not checked by `dependencies/R2`.

File and package selections limit findings while loading the complete project
source graph for evidence. `--since` and hook feedback scan the full current
project after relevant source or policy changes, including deleted and renamed
sources, so unchanged importers are reconsidered. No relevant changes produce
empty, incomplete coverage rather than a whole-project compliance claim.

## Agents

`odx guidance write AGENTS.md` or `odx guidance write CLAUDE.md` generates portable
Markdown with applicable rules, corrections, exact selectors, evidence limits, and
separately labeled reviewer advice. Add one package path for scoped instructions.
Document paths are relative to the project root; absolute paths also work.
`odx for --emit-md [path]` emits the same block to stdout; `--emit-claude-md` remains an alias.
Enforcement does not depend on an agent reading Markdown.

`odx guidance check <markdown-file> [package-path]` is nonmutating: exit 0 means
current, 1 missing/stale, 2 malformed ownership, invalid configuration, or IO error.
Repeat the same scope when checking or writing. CI can run this alongside `odx check`.
Freshness includes effective configuration, rule contracts, discovered selected
packages/roles, and generator revision. JSON5 comments and map order do not cause
churn; source body changes alone do not stale instructions. Builtin changes require
a rebuilt binary; local `.odx/topics` overrides load directly. A current document
does not certify source compliance or the actual compiler selected at check time.

The writer owns exactly one section between `<!-- odx:begin v1 -->` and
`<!-- odx:end -->` on separate lines. It preserves surrounding bytes and existing
permissions, rejects symlinks/nonregular files and ambiguous markers, and replaces
via a temporary file in the same directory. For an old unmarked `## odx` section,
manually put markers around only its generated text before regenerating; the tool
will not guess which human text to replace. Keep reserved marker text out of policy prose.

`odx init --hooks` also writes a PostToolBatch hook running `odx hook edit` and a
managed `CLAUDE.md` section. The hook checks relevant edits and reports without
blocking; ordinary checks and hooks never regenerate guidance.

The loop that blocked a session until `odx check` was clean was piloted on ten tasks under
three conditions before being removed:

| condition               | compiled | tests pass | turns |
| ----------------------- | -------- | ---------- | ----- |
| bare                    | 10/10    | 9/10       | 71    |
| `odx for` in the prompt | 8/10     | 7/10       | 66    |
| edit + stop hooks       | 8/10     | 7/10       | 104   |

The independent columns regressed under both odx conditions and the hook cost 46% more
turns. A rerun of the two failing tasks passed everywhere, so the failures were noise, but
there is no evidence in favour either. The raw rows are in the git history of this file.

## Adopting, ignoring, layout

`odx baseline regen` writes `odx.baseline`, one `<rule>\t<package>\t<subject>` line per
current violation, keyed on the subject (an import path, a symbol), never a line number.
Baselined findings still print and still appear in `--json`; they stop failing the build.
A full run drops entries that no longer fire; `--ci` fails instead of rewriting. Growth needs
`odx baseline add`.

`// odx:ignore <topic>/<R> reason: <ten+ characters>` above or at the end of a line
suppresses one finding; `odx:ignore-file` on lines 1-3 suppresses it for the file. A near
miss is `odx/bad-ignore`, an ignore that suppresses nothing is `odx/stale-ignore`. Every rule
is ignorable unless configured otherwise. `rules/`, `odx.json5` and
`tests/fixtures/` are reviewed like any other source.

- `odx/` the tool. `rules/<topic>/` built-in topics, embedded into the binary.
- `tests/fixtures/<name>/` small projects with `// want: topic/R2` markers, diffed both ways
  by `odx self-test`; `tests/fixtures/contract/` is one package per rule, fires and silent.
- `tests/compiler/` constructs the compiler now rejects on its own; `mise run audit` fails if
  one ever compiles again.

```
mise run ci   # build, unit tests, self-test, exemplars, audit, doctor --ci, odx on itself
```

## Future Tests:

Against this codebase, this tool should:

- Detect code like `if boolean { return ... }` then error/warn and prefer `if boolean do return ...`
