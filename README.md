# odx

See the [architecture and incremental contract](docs/milestones/2-architecture-and-incremental.md)
for milestone 2 decisions, graph boundaries, and validation.

The [analysis and coverage contract](docs/milestones/1-analysis-and-coverage.md)
defines what each check establishes. Dependency checks load the project source
graph even when findings are scoped to selected files or packages. Generated guidance can still disagree
with rule scope; the [original baseline](docs/milestones/0-contract-and-baseline.md)
records that remaining work.

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
| `allocators/R1`   | pure/service files start with `#+vet explicit-allocators`                                                             | file tag                             |
| `dependencies/R2` | ordinary imports obey `may_import` and `deny`, including denied imports reached through project production source | native AST and project source graph |
| `dependencies/R3` | no mutable package-level variables in pure/service packages                                                           | AST                                  |
| `errors/R3`       | an exported proc whose last result is an error type carries `@(require_results)`                                      | compiler entity table (`odin doc`)   |

Roles are opt-in: `odx.json5` assigns `pure`, `service` or `edge` per package directory and
says who may import whom. A package with no role gets no rule. `errors/R3` decides what an
error type is from the checked entity table: a name ending in one of `errors.types` (default
`["Error"]`), or, whatever its name, an enum with a `None`/`Ok` variant or a union that admits
`nil`. Nothing else in the Odin toolchain rejects a dropped error result: `x, _ := f()` and a
bare `g()` both pass `-vet -vet-cast` on dev-2026-09.

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
for calls and import globs, `exported` and `requires_param: { index, type_suffix }` for
procedures, `at: "package_scope", mutable: true` for declarations, plus `roles`/`except_roles`.
`odx rule try '<check json5>' [paths]` prints every match before any file exists,
`odx rule add <topic>` scaffolds the next id, `odx rule test <topic>/<id>` compiles its
blocks. The evidence bar is the one `allocators/R1` and `errors/R3` meet: a compiler version
and a command whose output shows the failure. Anything less stays a reader check.

## Commands

```
odx check [<path>...] [--json] [--since <ref>] [--fast] [--ci]   exit 1 on violations
odx doctor [--ci] [--json]        guarantees, toolchain, config, mise.toml drift
odx for <path> [--brief]          the rules that apply to a file or package
odx for --emit-claude-md [<path>] the same as a Markdown section for CLAUDE.md
odx explain [<topic>] [--rule R3] rules, rationale, fires/silent
odx explain --checklist           the reader checks, for a reviewer
odx ignores [--stale]             every odx:ignore; --stale: suppressing nothing
odx baseline add | regen          freeze current violations by semantic key
odx hook edit                     Claude Code PostToolBatch hook: report, exit 0
odx init [--hooks]                write odx.json5 and mise.toml (--hooks: hook + CLAUDE.md)
odx self-test                     fixtures and every rule block
odx rule try | add | test         draft, scaffold, test a rule
```

Exit codes are contract: `0` clean, `1` violations, `2` tool or config error; `hook edit`
always exits 0. `--json` on `check` is the machine contract, `schema: 1`; fields are only
added under that number. Each violation carries `file`, `line`, `col`, `rule`, `severity`,
`check`, `message`, `class`, `subject` (the baseline key), `baselined`, `ignorable`,
`statement`, `why`, `fires`, `silent`, `fix_hint` (the rule's `instead_of`) and
`ignore_syntax` (the exact suppression comment), plus `blocking`, always true, kept for the
schema. `summary` carries `errors`, `warnings`, `ignored`, `files`, `baselined` and
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

`odx init --hooks` writes two things: a PostToolBatch hook running `odx hook edit`, which
checks the project after relevant edits (compiler first, then rules) and prints findings without ever
blocking, and a `CLAUDE.md` section generated by `odx for --emit-claude-md`, so the rules sit
inline where they cost nothing per turn. Regenerate the section after editing `rules/`.

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
is ignorable. `rules/`, `odx.json5` and `tests/fixtures/` are reviewed like any other source;
the generated `CLAUDE.md` tells an agent to ask before editing them.

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
