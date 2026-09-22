# Milestone 0: product contract and baseline

Status: complete for milestone 0; later enforcement guarantees remain unimplemented.
Recorded 2026-09-21 (America/Denver; execution crossed into September 22 UTC).
Source baseline: `c7eef38877f643e7d0e42616892a1f99ad1c645c`.

## Decision and scope

odx is a project policy engine with optional example conventions. Project authors
choose restrictions and supply their rationale. Small policies must be practical;
strict policies must be possible without changing odx or adopting its role names.
This is the product direction for subsequent milestones, not a claim that today's
defaults and generated guidance already satisfy it.

| Responsibility | Contract |
| --- | --- |
| Mechanical policy | Report violations of explicitly selected, bounded contracts using source, AST, or compiler evidence. Identify the evidence and coverage limits. |
| Compiler | Own language validity, type checking, compiler vet checks, and attribute semantics. odx can configure, invoke, and report these checks. |
| Formatter | Own mechanical layout through odinfmt; do not build another formatter into odx. Compiler style flags remain selectable. |
| Review advice | Label intent, ownership, API ergonomics, and meaningful error handling as advice unless a narrow mechanical guarantee has been demonstrated. Compiling advice examples proves validity only. |
| Runtime tests | Establish observed behavior under their inputs, including allocation and lifetime properties; source patterns alone do not prove these properties. |
| Human or agent consumer | Read ordinary Markdown and structured findings. No model call, agent vendor, hook installation, or obedience to prose is part of enforcement. |

A clean authoritative result should eventually mean that all selected supported
checks completed for the declared scope. Today's exit 0 does not establish that
stronger promise: fast checks omit compiler evidence and scoped dependency checks
can miss violations. Users must be able to distinguish unavailable evidence from
successful checks before those guarantees can be advertised.

Alternatives considered:

| Approach | Benefit | Cost and decision |
| --- | --- | --- |
| Mandatory built-in style with exceptions | Quick onboarding and consistent examples | Makes a two-rule project inherit unrelated advice. Reject as the product contract; retain built-ins during compatibility work. |
| Project policy engine, optional examples | Supports independent minimal and strict policies; existing local topics provide a starting point | Requires accurate scope, defaults, and authoring semantics. Selected. |
| Architecture-only tool | Smaller analysis surface | Drops project coding conventions from the requested outcome. Reject. |
| Thin coordinator of compiler, formatter, and linters | Avoids duplicate analysis | Still needs a way to express project contracts and synchronize guidance. Retain composition as an implementation option, not the whole scope. |

No new parser, preset system, cache, plugin runtime, or built-in rule is justified
by this milestone. Native parsing is an existing asset; milestone 1 must compare
evidence sources before making the backend decision.

## Two representative policy needs

These are synthetic design cases, not interviews, external adoption evidence, or
a claim that the complete policies already work. Milestone 6 must demonstrate
them end to end after correctness work.

### Minimal library

A small parsing library wants just two source restrictions: no mutable
package-level declarations and no direct foreign declarations. It needs no
architecture roles, allocator signature convention, or prescribed error naming.
Compilation and formatting run separately with the project's chosen flags.

- Violation: `count: int` at package scope. Compliant: `count :: 3`, a `count`
  struct field, or state supplied as a procedure parameter.
- Violation: a direct `foreign import` or foreign procedure block. Compliant:
  ordinary Odin declarations, including a string or comment containing the word
  `foreign`.
- Legitimate counterexample: a predicate returning `bool` is not an error API;
  it should not acquire typed-error advice merely by using odx.
- Adversarial boundary: a dependency can use foreign code even when this package
  contains no foreign syntax. This policy makes no transitive no-foreign claim.
  Conditional and nested declaration coverage needs milestone 1 proof.

Current selectors can express these direct declaration checks with empty role
filters. The executable probe compiles `count: int` alongside `limit :: 3`, reports
only the mutable declaration, and then accepts the constant alone. No-role
custom enforcement works; default guidance still leaks unrelated conventions.

### Strict application core

A stateful application separates `domain`, `adapters`, and `app` packages. The
domain may not reach OS/network facilities through project dependencies, declares
no mutable package state or foreign bindings, and exposes deliberately selected
error APIs with required-result attributes. Allocating APIs document ownership;
where desired, files opt into the compiler's explicit-allocator vet tag.

- Violation: a domain package imports an adapter which imports `core:os`.
  Compliant: domain code consumes a capability supplied by a caller. The existing
  `dependencies_r2_via` fixture is a compiled adversarial case: its immediate
  import is allowed but its transitive reach is denied.
- Violation: domain package variable `cache: Cache`. Compliant: caller-owned
  `Cache` passed by pointer; mutable process state in `app` may be legitimate.
- Violation: an API selected by the project's error contract lacks
  `@(require_results)`. Compliant: the attribute on that API. A lookup success
  flag, optional value, or two distinct error domains is not automatically a
  violation. The attribute does not prove useful caller recovery.
- Ownership review should accept arena-managed allocations when the caller owns
  the arena. Requiring a textual `defer delete` would be a false positive.
  Conversely, the presence of `defer` alone is not proof of correct lifetime.

Current dependency configuration accepts custom roles, but guidance selection,
transitive scoped checks, and error-type inference prevent claiming this whole
experience works. Custom error selection and allocator exemptions remain design
requirements, not new promises of current selectors. The existing compiled
contract and rule examples supply initial examples; exhaustive strict-policy
proof belongs to milestones 1–6.

## Reproducible baseline

Run from the repository root:

```sh
export ODX_ODIN=/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin
export PATH="/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09:$PATH"
mise run --force ci
"$ODX_ODIN" run docs/milestones/0-probe.odin -file -out:build/milestone-0-probe > /tmp/odx-m0-probe.json
```

The Odin probe creates and removes temporary projects, reads
existing fixtures, captures command exit codes and JSON findings, and emits its
observations as named results with exit codes and captured stdout/stderr (check
stdout contains JSON). It is deliberately not a CI assertion that known bugs must persist.
Later milestones should turn counterexamples into regressions requiring correct
behavior. Inspect `exit`, `stderr`, and `tool_errors` before interpreting reports.

Original baseline toolchain: macOS arm64, `/opt/homebrew/bin/odin version
dev-2026-09:a2fb372b7`; mise pins `dev-2026-09`. Doctor identifies the compiler as
`dev-2026-09-nightly:a2fb372`. No other platform/toolchain was tested.

The reference installation for subsequent work is
`/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09`, including its compiler,
`core`, `base`, `vendor`, and examples. Its compiler reports
`dev-2026-09-nightly:a2fb372`. Consult those installed sources for syntax, APIs,
and idiomatic Odin; prefer Odin for executable probes and scripts. The replacement
probe requires `ODX_ODIN` explicitly so its compiler invocation and odx's compiler
subprocesses use the same reference installation.

The Odin replacement was compiled with `-vet -strict-style` and executed against
a fresh odx build from that installation. All listed probe behaviors reproduced;
self-check now covers 31 files because the probe itself is Odin source. The
original full-CI result below remains the historical baseline, not a claim of a
second full-CI run.

The pre-existing binary had SHA-256
`4afee71be1780f9a8b7f6e9760bdadf13bec5ff1fbc98b1b983fc2c5c3dd79e2`.
Its source provenance was unavailable, so it was not trusted. A forced source
build produced
`ca38e2a3626b7dccbe950c8b7e3dba5117befd3cf7c5bf01c9ea6ea02f13b20f`.
Different hashes do not prove different source because builds need not be
reproducible; every runtime conclusion below uses the fresh build.

### Observed runtime results

| Probe | Result |
| --- | --- |
| Full CI | Exit 0: 13 unit tests, five fixture projects, every executing rule and reader example, four exemplar packages, redundancy audit, doctor, and self-check pass. |
| Doctor | Zero errors, two warnings: missing edit-hook configuration and allocator topic with no matching project role. CI success does not mean zero warnings. |
| Self-check with `--ci --json` | Exit 0, 30 files, no findings or tool errors. |
| Contract fixture, `--topic dependencies` | Exit 1, 13 files, three findings; includes `dependencies_r2_via/fires.odin:4`, reaching `core:os` via `dependencies_r2_svc`. |
| Same topic, selected `dependencies_r2_via` | Exit 0, two files, no findings or tool errors. Confirmed false negative. |
| Local `dependencies/R9`, warning severity | One warning; exit 0 normally, exit 1 with `--strict`. JSON still has `blocking: true`. |
| Same-name local topic | `explain --json` contains only local R9, `overrides: true`; built-in dependencies R2/R3 disappear. Replacement is whole-topic, not a rule merge. |
| Topic roles `edge`, rule roles `domain` | Rule reports in a domain package; path-specific generated Markdown omits it. Whole-project emission includes it and describes the topic as applying to edge. |
| Disabled local R9 | Strict check is clean; whole-project emitted Markdown omits the rule. |
| Existing Markdown section | `init --hooks` advises manual refresh and preserves the stale sentinel and human text. It installs a hook only inside the temporary project. |
| Custom rule without role filters, no configured roles | Mutable declaration still produces a warning. The README's blanket no-role/no-rule statement is too broad. |
| Constant counterexample | Replacing the mutable variable with just a constant yields exit 0 even under strict mode. |

The graph probe intentionally uses the same topic filter in full and scoped runs
and runs compiler checks (no `--fast`). It isolates reporting scope as the changed
variable. It does not establish every `--since`, file, or hook failure mode.

### Static findings, distinct from runtime proof

- [checks.odin](../../odx/checks.odin): `make_ctx` loads selected packages;
  `reach_denied` searches that set. Imports are parsed source, not a compiler
  graph. External packages are traversal boundaries. `fix_hint` copies
  `instead_of`; the runtime graph finding indeed recommends the discouraged
  practice in that field.
- [topics.odin](../../odx/topics.odin) and
  [pattern.odin](../../odx/pattern.odin): accepted fields are not completely
  constrained per matcher; procedure matching does not consume `name`.
  Matcher-by-matcher reproductions remain milestone 3 work.
- [commands.odin](../../odx/commands.odin): generation uses topic roles while
  execution uses check roles. Whole-project emission includes all topics;
  disabled rules are omitted but topic summaries and reader advice remain.
  No freshness check is implemented, and the refresh instruction mentions only
  `rules/`, omitting config and local topics.
- [project.odin](../../odx/project.odin): packages are parsed regardless of
  platform. [check_cmd.odin](../../odx/check_cmd.odin) skips compiler and entity
  families under `--fast`; the report lacks an explicit per-check coverage list.
- [git.odin](../../odx/git.odin): changed-source selection filters to existing
  `.odin` paths. Config-only edits and deletions need explicit coverage decisions.
- Built-in prose promises allocator exemptions and foreign/graph knowledge
  beyond demonstrated checks. Structural error inference can include optional
  values. These are semantic audit inputs for milestone 5, not validated doctrine.

Unresolved: active-target versus all-source semantics, incomplete compiler data,
alias/shadow resolution, conditional foreign syntax, excluded dependencies,
reverse-impact scanning, baseline identity collisions, and actual external user
requirements. None is certified by the green baseline suite.

## Comparison with neighboring tools

Primary documentation was retrieved on 2026-09-21. Only Odin and odx were executed;
other rows describe published capabilities, not independently tested correctness.
Remote master documentation may move; repeat this survey before release.

| Tool | Representative requirement and evidence | Project-authored policy boundary |
| --- | --- | --- |
| Odin compiler | Installed `odin check -help` exposes vet/style flags, warnings-as-errors, JSON errors, dependency export, and an import graph. Fresh CI compiles the rule examples. | Selects compiler-owned checks; does not document a text-authored arbitrary policy-rule interface. Exported graph availability is a candidate for milestone 1, not proof odx currently uses it. [Compiler source](https://github.com/odin-lang/Odin/blob/master/src/main.cpp). |
| OLS / odinfmt | OLS documents compiler diagnostics, target profiles, collections, and formatting through odinfmt. Appropriate for editor feedback and layout. | Configuration selects tooling behavior; the surveyed README does not establish authoring new project AST rules or transitive architecture policies. [OLS documentation](https://github.com/DanielGavin/ols). |
| OLT / odintooling | Publishes configurable naming and allocation/error checks, suppressions, selected rule execution, JSON/SARIF, and LSP integration. Could cover projects whose needs match its catalog. | The documented TOML changes built-in domains/parameters; no new-rule authoring interface was established in this survey. Published resource-safety claims require counterexample testing before treating them as guarantees. [OLT documentation](https://github.com/RainerXE/odintooling). |
| ast-grep | Supports custom languages by loading a compiled Tree-sitter grammar and registering it in project configuration. Candidate for project-authored structural patterns. | Adds grammar distribution and compatibility work. Custom-language registration alone establishes neither Odin type resolution nor project dependency reach. Odin-specific comparison remains milestone 1 work. [Custom-language documentation](https://ast-grep.github.io/advanced/custom-language.html). |
| odx today | Local Markdown rules author new combinations of existing selectors without rebuilding; rationales, examples, findings, and guidance share rule metadata. | New selector algorithms still require code. The baseline proves scope and guidance defects; this is not a novelty or superiority claim. |

The selected direction complements compiler and formatting tools. Neither a fixed
lint catalog nor an available pattern engine alone establishes the combined
project-policy contract. This is an inference from the surveyed interfaces, not
an exhaustive assertion that no alternative can satisfy it.

## Compatibility inventory and consequences

Preserve these public surfaces until an explicit later compatibility decision:

- Commands: `check`, `doctor`, `for`, `explain`, `ignores`, `baseline add|regen`,
  `hook edit`, `init`, `self-test`, and `rule try|add|test`; their path, topic,
  exemplar, JSON, fast, strict, since, CI, and output-limit options.
- Config version 1: custom/default roles, overlap validation, exclusions,
  dependency allow/deny lists, disabled reasons, compiler configuration,
  collections, allocator-tag mode, error-type suffixes, and compiler path
  precedence (`ODX_ODIN`, configured path, PATH).
- Embedded topics plus whole-topic local overrides; rule IDs and frontmatter;
  all five check kinds and public call/import/proc/decl/foreign matchers.
  Reader prose and executable examples are separate from enforceable rules.
- Schema 1 findings and summary fields, semantic subjects, repair hints,
  suppression syntax, and `blocking`. Correcting misleading meanings needs
  consumer consideration even when JSON field names stay unchanged.
- Exit 0 includes ordinary warnings and baselined debt; strict promotes warnings
  to failing status. Findings use exit 1, tool/config failures exit 2, and the
  edit hook always exits 0. Early config failures need not emit JSON.
- Baselines use rule/package/subject keys; full ordinary checks may shrink the
  baseline, CI reports stale debt instead of rewriting. Suppressions require
  reasons and stale-use checks. Keep adoption mechanisms pending milestone 7.
- Initialization writes config/tasks and optionally hook/guidance files.
  Generated Markdown is a portable artifact despite the current Claude-specific
  command/file names. Do not silently alter human content or install integrations.

No production behavior changes in milestone 0, hence no migration or runtime
performance cost. The probe uses Odin and the host's `git` and `shasum` commands;
it does not add a product dependency or CI step. Its tiny synthetic cases and the
approximately four-second local CI run are not performance benchmarks.

Acceptance: scope and alternatives are recorded; contrasting policies have
violations, legitimate counterexamples, and adversarial boundaries; baseline
claims distinguish execution, inspection, and unknowns; public surfaces are
inventoried; enforcement is independent of AI. Revisit the product decision if
real projects cannot express their needed bounded policies without excessive
configuration, or comparative proofs show existing tools cover those needs more
simply. Milestone 1 is next; no later milestone is complete.
