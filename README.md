# odx

odx checks project-selected Odin policies and generates matching instructions for
people and coding agents. Projects own their rules, role names and exceptions.
Checks can fail CI; the optional edit hook reports findings and exits 0. odx never
calls an AI model.

**Experimental source build:** the assessed scope is macOS arm64 with Odin
`dev-2026-09-nightly:a2fb372`. Linux CI is configured but its current result is
unverified here; Windows and other compiler revisions are unverified.
No agent-productivity benefit or independent-user adoption is established.

With [mise](https://mise.jdx.dev/) installed, build from this checkout and try a
copyable policy:

```sh
mise install
mise run build
./build/odx check --ci --json --root examples/policies/minimal
./build/odx for --emit-md --root examples/policies/minimal
```

The [minimal library](examples/policies/minimal/README.md) chooses two source
rules without roles. The [strict application](examples/policies/strict/README.md)
chooses five constraints using its own role names. Copy either directory,
including `.odx`, and customize its rules and configuration. `mise run release`
creates an optimized local binary; no packaged cross-platform release is implied.

Source patterns establish bounded syntax facts; compiler evidence covers the
selected build configuration. Neither establishes runtime purity, allocation
freedom, correct lifetimes or all-path cleanup. Error classification can be a
project-selected heuristic. Reviewer advice remains explicitly unenforced.
Formatting stays with the project's formatter.

The declaration selector's `mutable: true` follows the AST's variable-declaration
flag, including `@(rodata)` declarations. It does not establish writable storage
or harmful shared state. Review this boundary before adopting a no-globals policy.

## Guarantees

`odx doctor` audits configured compiler flags, recognized flags advertised by the
installed compiler, file opt-outs and allocator-tag coverage. These are bounded
configuration checks, not a list of every language or runtime guarantee. A project
can adopt a flag or record its reason for declining it in `odin.declined`, for
example `{ "-vet-style": "why this project declines the flag" }`.
`odin.tagged_files_min` sets a project-selected minimum for allocator-tag coverage.
`doctor --json` returns
`{schema, errors, warnings, guarantees: {flags: [{flag, on, declined}], tagged, needed}}`.

`odx check` enforces the per-file half: a missing allocator tag is `allocators/R1`, a
`#+feature` opt-out without a `// reason: <why>` on its line is `odx/feature-optout`, a
`#+vet !x` not listed in `odin.allowed_vet_disables` is `odx/vet-disable`.
The latter two audits default on. Set `odin.audit_file_tags: false` to opt out;
their coverage becomes `not_applicable`, and the unused vet-disable allow-list
is not audited for staleness. This does not disable allocator-tag rules, compiler
diagnostics, or validation of odx suppressions. `doctor` remains a separate
configuration audit with its own recommendations.

## Rules

Four rules, all mechanical, all counting:

| rule              | what                                                                                                                  | how                                  |
| ----------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `allocators/R1`   | selected files contain `#+vet explicit-allocators` before the package declaration | file tag |
| `dependencies/R2` | ordinary imports obey `may_import` and `deny`, including denied imports reached through project production source | native AST and project source graph |
| `dependencies/R3` | no mutable package-level variables in pure/service packages                                                           | AST                                  |
| `errors/R3`       | exported non-test procedures whose named final result matches project error classification carry `@(require_results)` | compiler entity table (`odin doc`) |

Roles are opt-in: `odx.json5` assigns project-chosen role names per package
directory and says who may import whom. The built-in examples use `pure`,
`service` and `edge`; those names are not required. Unrestricted rules also apply to packages without a role;
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

`explain --checklist --json` returns reader advice as `{topic, roles, advice}` records.

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
blocks. Record reproducible source or compiler evidence, the toolchain used, and
matching boundaries. A source policy may intentionally reject compiler-valid
code; compiling examples establishes validity, while odx findings establish the
selected restriction. Intent-dependent claims stay in reviewer advice.

Rule examples run in a scratch `sample` package assigned the rule's `role`
(default `edge`). They retain project compiler settings, error classification,
disabled rules and dependency layers. An explicitly tested rule is enabled for
both blocks even if disabled in the project. Source paths and role globs are
synthetic; snippets must supply their own required declarations and imports.
Relative collection settings are rebased to their original locations, but
outside-project dependencies still respect the documented graph boundary.
Other applicable rules must also accept each example.

Optional rule frontmatter `fix_hint` gives a nonempty desired correction. If absent,
the rule statement is the compatibility fallback. Keep rationale in `why` and the
discouraged alternative in `instead_of`; hints are guidance, not automatic edits.

## Commands

```
odx check [<path>...] [--json] [--since <ref>] [--fast] [--ci]   findings and coverage
odx doctor [--ci] [--json]        guarantees, toolchain, config, mise.toml drift
odx for <path> [--brief]          the rules that apply to a file or package
odx for --emit-md [<path>]       portable managed Markdown (--emit-claude-md alias)
odx guidance check|write <markdown-file> [<package-path>]  verify or regenerate guidance
odx explain [<topic>] [--rule R3] rules, rationale, fires/silent
odx explain --checklist           the reader checks, for a reviewer
odx ignores [--stale]             every odx:ignore; --stale: suppressing nothing
odx baseline add | prune | regen  explicitly accept, prune, or replace accepted debt
odx hook edit                     Claude Code PostToolBatch hook: report, exit 0
odx init [--hooks]                write odx.json5 and mise.toml (--hooks: hook + CLAUDE.md)
odx self-test                     fixtures and every rule block
odx rule try | add | test         draft, scaffold, test a rule
```

`--json` is supported on `check`, `doctor`, `for`, `explain`, and `ignores`;
unsupported commands reject it. Project-loading failures in JSON mode return
structured tool errors. Invalid command syntax can still report errors on stderr.

Check exit codes are contract: `0` no unbaselined errors (warnings also fail with
`--strict`), `1` failing findings, `2` tool or config error. Coverage must be inspected
separately: partial scans can exit 0. `hook edit` always exits 0.
`--json` on `check` is the machine contract, `schema: 1`. Each violation carries `file`, `line`, `col`, `rule`, `severity`,
`check`, `message`, `class`, `subject` (a semantic label), `baselined`, `ignorable`,
`statement`, `why`, `fires`, `silent`, `fix_hint` (the desired repair) and
`ignore_syntax` (the exact suppression comment), plus `blocking`, always true, kept for the
schema, not an exit-status decision. `fix_hint` describes a repair; `instead_of` describes discouraged behavior.
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
a baseline.

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

Public validation overlays the example policies on pinned Odin demo and queue
source. It tests findings, repairs, baseline maintenance and guidance freshness;
it does not measure independent adoption or agent productivity. An earlier small
agent pilot did not establish improved correctness or productivity.

## Adopting, ignoring, layout

Baselines support gradual adoption without hiding findings. Format 2 binds each
accepted occurrence to its rule, relative file, subject, line/column, and a SHA-256
snapshot of the whole source file. Findings without a source-file identity are
ineligible. Any source-file edit, including formatting or an enclosing procedure
rename, reopens its findings. Byte-identical source recreated at the same path
and position has the same identity; this is a snapshot contract, not history tracking.

Ordinary checks and CI never rewrite `odx.baseline`. A complete full check reports
stale entries as an error; partial or failed checks cannot certify resolution.
Use `baseline add` to accept new eligible occurrences while retaining existing
entries, `baseline prune` to remove resolved entries without accepting new debt,
and `baseline regen` to replace acceptance with the current eligible findings.
Every write requires complete whole-project analysis. Review the resulting diff.
Baselined findings remain visible, retain their severity, and do not fail strict mode.

Version 1's package/subject keys cannot identify historical occurrences safely.
Checks reject old or malformed formats instead of accepting ambiguous debt.
Explicit `baseline regen` migrates by accepting **current** eligible findings;
it is a new adoption decision, not a reconstruction of old acceptance or reasons.

`// odx:ignore <topic>/<R> reason: <ten+ characters>` above or at the end of a line
suppresses matching findings for that rule on its target line; `odx:ignore-file`
on lines 1-3 suppresses them for the file. The literal `reason:` marker is required. A near
miss is `odx/bad-ignore`, an ignore that suppresses nothing is `odx/stale-ignore`. Every rule
is ignorable unless configured otherwise. `rules/`, `odx.json5` and
`tests/fixtures/` are reviewed like any other source.

`ignores --stale` is a read-only suppression audit: exit 0 means complete evidence
with no malformed or stale suppressions, 1 means such a suppression was found,
and 2 means required evidence is incomplete or a tool failed. `--json` returns a
check report including coverage and findings; unrelated policy findings do not
fail this specialized audit. Baseline debt does not affect suppression staleness.
The ordinary `ignores --json` listing retains its `{ignores, bad}` shape.

- `odx/` the tool. `rules/<topic>/` built-in topics, embedded into the binary.
- `tests/fixtures/<name>/` small projects with `// want: topic/R2` markers, diffed both ways
  by `odx self-test`; `tests/fixtures/contract/` is one package per rule, fires and silent.
- `odx/*_test.odin` native unit tests. `tests/integration/*/*_test.odin` native CLI and whole-project tests.
- `tests/validation/*_test.odin` serial public-source evaluation, kept outside CI timing noise.
- `tests/compiler/` constructs the compiler now rejects on its own; `mise run audit` fails if
  one ever compiles again.

```
mise run test # native Odin unit and integration tests, including whole example projects
mise run ci   # tests, fixtures, exemplars, compiler audit and repository self-check
```

Run the serial real-source evaluation separately from CI:

```sh
mise run validation   # repeat the public, pinned real-source policy pilots
```
