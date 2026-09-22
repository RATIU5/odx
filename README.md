# odx

Project-owned Odin policies, with deterministic checks and concise context for
humans and external coding agents. odx never calls a model. It complements the
Odin compiler, odinfmt, OLS and other analysis tools; it does not replace them.

Experimental source build: assessed on macOS arm64 with Odin
`dev-2026-09-nightly:a2fb372`. Linux CI is configured; broader platform/toolchain
support and independent-user adoption remain unverified. No agent-productivity
benefit is established.

```sh
mise install
mise run build
./build/odx check --root examples/policies/minimal --json
./build/odx policy --root examples/policies/minimal
```

Copy an example, including its `.odx` directory, to start a project:
[small library](examples/policies/minimal/README.md),
[strict application](examples/policies/strict/README.md), or
[compact conditionals](examples/policies/compact-if/README.md).

## Commands

```sh
odx check [paths...] [--topic NAME] [--fast] [--strict] [--since REF]
          [--max-violations N]
odx policy [path] [--topic NAME] [--rule ID] [--checklist]
           [--write FILE | --verify FILE]
odx baseline add|prune|regen
odx ignores [--stale]
```

All commands support `--root DIR` and `--json`. JSON is schema 2; invalid arguments
and configuration also produce structured errors. Unsupported flags are rejected.
`odx help` lists the interface. Paths select packages, including when a file is
supplied. Normal checks never rewrite source, baselines or instructions.

`check` exits 0 for no failing unaccepted findings, 1 for findings, 2 for tool or
configuration errors. Warnings fail only with `--strict`. Inspect coverage even
on exit 0: a fast or empty incremental check cannot certify complete analysis.

`policy` prints effective rules and separately labeled reviewer advice. Use
`--topic errors --rule R3` for one applicable rule, or `--checklist` for advice.
Without discovered packages, `catalog: true` identifies conditional policy rather
than established applicability. JSON returns packages, rules and advice; it does
not expose internal rule-storage fields or repeat the full configuration.

## Strict syntax boundaries

A local rule can require `do` for a simple conditional:

```json5
check: { kind: "pattern", match: "if" },
severity: "warning",
fix_hint: "Use if CONDITION do STATEMENT for one return, call, or assignment.",
```

```odin
if failed { return err }  // finding: use if failed do return err
if ready { process() }    // finding: use if ready do process()
if ready do value += 1    // accepted
```

This opt-in matcher inspects a braced then-body without an `else` or membership
in an `else if` chain. Exactly one return, call statement or assignment qualifies,
regardless of line count. Existing `do`, multiple statements, declarations,
`defer` and nested control statements do not qualify. Independent conditionals
inside nested procedures or branches are still checked. Comments and strings
are not statements. “One” counts syntax, not runtime effects; one call may have
many effects. Findings recommend a change and never rewrite comments or source.

The compact-conditionals example deliberately contains three warning cases.
`check --strict` fails it; its native Odin tests still pass. Change the rule's
severity to `error` to fail ordinary checks too. No additional command or parser
is needed.

## Policies and evidence

`odx.json5` selects optional package roles, dependency boundaries, compiler flags,
exclusions and disabled rules. Role names are project-defined. Local
`.odx/topics/<topic>/` directories replace the corresponding built-in topic.
A rule is `<id>.odx.md`: JSON5 frontmatter with `statement`, `why`, `instead_of`,
`evidence`, `cost`, `severity` and `check`, followed by prose/examples. Optional
`fix_hint` describes the desired repair; otherwise the statement is used.

Pattern matchers are `call`, `import`, `proc`, `decl`, `foreign` and `if`.
Selectors reject fields that do not apply to their matcher. `policy --json`
exposes the exact effective selector. Add or edit local files, run `check`, and
keep positive/negative source cases in ordinary Odin tests or example projects.
Repository native tests also verify the retained built-in/local Markdown examples.

Built-in policies cover leading explicit-allocator directives, configured ordinary
import boundaries, package-scope variable declarations in selected roles, and
result attributes on selected exported APIs. These are project conventions:

- Allocator directives do not prove allocation freedom, ownership or lifetime.
- Declaration matching includes inactive branches, foreign containers and
  `@(rodata)` variables; it does not establish writable storage or harmful state.
- `errors.types` matches canonical named final-result suffixes. The compatibility
  default `errors.structural: true` also recognizes named None/Ok enums and
  nil-able unions. Set it to false to avoid classifying optional/status shapes.
- `@(require_results)` requires acknowledgement, including explicit discard; it
  does not prove error handling. Anonymous and non-final results are outside scope.
- File feature opt-outs require a nonempty same-line `// reason: ...`; vet disables
  must be allowed by configuration. `odin.audit_file_tags: false` disables these
  two audits. `odin.forbidden_flags` rejects matching configured compiler flags.

Native checks inspect collected source, including inactive/platform/test files.
Compiler diagnostics and entity checks cover the selected build configuration;
checks do not execute tests. Required unavailable evidence is explicit, not clean.

Import `may_import` checks direct role/path matches; `deny` also follows included
project production imports. Built-in collection imports are opaque leaves.
Required missing, excluded, unknown-collection or outside-project edges are
unsupported evidence. The selected package's tests count; dependency test files
do not. This proves neither foreign-access freedom nor runtime purity.

Scoped syntax checks load selected packages. Applicable dependency checks load
the full project graph, while reporting only the selection. `--since REF` scans
the full current project after relevant source/policy changes so unchanged
importers are reconsidered; no relevant changes report empty, incomplete coverage.

## Machine output

Check JSON contains `schema`, `violations`, `rules`, `coverage`, `summary` and
`tool_errors`. Each violation includes location, rule ID, check provenance, severity, message,
subject, baseline state and suppression information. Look up `rules[v.rule]`
for shared repair text, rationale, examples and evidence boundaries when present.
Coverage rows refer to the same rule IDs instead of repeating evidence prose.

Summary counts are computed before `--max-violations` truncation; `omitted`
records the remainder. Baselined findings remain visible and retain severity,
but do not fail checks. `coverage.complete` means required evidence completed
within the stated boundaries, not that the code is violation-free.

Schema 2 replaces per-finding repeated metadata and removes the obsolete
`blocking` field. Consumers of schema 1 must use the shared `rules` map.

## Instructions and adoption

```sh
odx policy --write AGENTS.md
odx policy --verify AGENTS.md
odx policy src/library --write AGENTS.md
```

Repeat the same scope on verification. Exit 0 means current, 1 stale/missing,
2 malformed ownership, configuration or IO failure. Managed writes own one
`<!-- odx:begin v1 -->` / `<!-- odx:end -->` section, preserve surrounding content
and permissions, reject symlinks/ambiguous markers and replace atomically.
Freshness includes effective configuration, rules, scope and generator revision.
Source-body edits alone do not stale instructions. Rebuild after built-in changes;
local policy changes load directly. Fresh instructions do not certify compliance.

Baselines bind accepted occurrences to rule, file, subject, position and whole-file
SHA-256. Any source edit reopens acceptance. `add` accepts new occurrences, `prune`
removes resolved entries and `regen` replaces acceptance with current findings.
Writes require complete whole-project evidence; checks never rewrite the baseline.
Old or malformed formats fail explicitly. A complete check reports stale entries
as an error until explicitly maintained.

`// odx:ignore topic/R1 reason: <ten+ characters>` suppresses the target line;
`odx:ignore-file` on lines 1–3 applies to the file. Malformed and ineffective
suppressions are findings. `ignores --stale` exits 0 for a clean complete audit,
1 for malformed/stale suppressions, 2 for unavailable evidence. Ordinary listing
returns `{schema, ignores, bad}` in JSON mode.

The former for/explain/guidance workflows use `policy`. Vendor hooks, initialization,
doctor and rule-authoring/test subcommands were removed. Copy example policy files
and use your existing build/editor tools. Doctor-only `odin.required_flags`,
`declined`, `tagged_files_min` and `version` are rejected; pin the compiler in your
build environment and configure sanitizer/test commands there.

## Development

```sh
mise run test        # native unit, fixture, compiler and whole-project integration tests
mise run ci          # tests and repository self-check
mise run validation  # serial pinned public-source evaluation with retained artifacts
```

The analysis API is `analyze(Analysis_Options) -> (report, exit_code)`; it does not
print or exit. CLI code validates arguments and renders results. Native AST and
compiler evidence feed the same findings/coverage model. No server, plugin runtime
or embedded agent is required.
