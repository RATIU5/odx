# Milestone 6: alternatives research

Research completed 2026-09-21. This is a capability comparison for the two
synthetic projects defined in milestone 0, not external adoption evidence.
Primary documentation was retrieved again; OLT, OLS and ast-grep were not run.
Installed Odin reports `dev-2026-09-nightly:a2fb372`.

## Recommendation

Use copyable local topics and configuration. Existing odx selectors express the
minimal library's two restrictions and the strict application's chosen source,
dependency, and result-attribute contracts. No new AST matcher, parser, metric,
or preset system is justified by these requirements. Fix configuration leakage
and example-testing inconsistencies if the end-to-end demonstrations expose
them; those are correctness gaps, not reasons to expand the policy catalog.

Compared with optional versioned presets, local files are transparent and need
no selection, version-resolution, or migration machinery. Their cost is manual
updates, mitigated here by executable examples and guidance freshness checks.
Compose compiler and formatter checks with these files rather than duplicating
their existing responsibilities.

## Candidate checks and competing capabilities

| Candidate | Current odx and boundary | Alternatives and decision |
| --- | --- | --- |
| Direct foreign syntax | `pattern/foreign` reports foreign imports and blocks, including package-level conditional containers. Ordinary imports of packages containing foreign code are outside this direct check. | Odin permits foreign bindings; no selected compiler flag replaces this project restriction. Generic structural patterns are an ast-grep candidate, but existing native parsing already supplies the needed distinction. Keep current matcher. |
| Mutable package declarations | `pattern/decl`, `at: package_scope`, `mutable: true` distinguishes variable declarations from constants, fields and procedure locals. It includes foreign-block declarations. | The compiler's `-disable-non-constant-globals` concerns initialization, not mutability. A standalone `counter := 0` with a procedure incrementing it passed `odin check -file -no-entry-point -disable-non-constant-globals` in this research. OLT's published catalog does not establish this exact configurable ban. Keep current matcher. |
| Required result attribute | `require_attribute` selects compiler-exported non-test procedures by configured final-result error classification; `errors.structural: false` avoids structural guessing. It is not an arbitrary attribute predicate over every declaration. | Odin enforces `@(require_results)` at call sites but allows explicit discard. OLT publishes discarded-error-result checks; their equivalence to this selected project contract is untested. Use existing classification and attribute check. |
| Syntactic API restriction | Call selectors match configured spellings, with import-name normalization; they do not prove callee identity under shadowing, aliases or indirect calls. | Compiler checks validate calls but do not establish the project's arbitrary deny list. OLT publishes checks for particular APIs. ast-grep can express structural call patterns with an appropriate grammar. Keep the existing bounded selector when a project explicitly wants that spelling restriction. |
| Naming | Current proc selectors do not implement arbitrary name filters or naming-style rules. | OLT publishes procedure/local snake-case and type PascalCase checks. ast-grep offers structural patterns, but an Odin naming policy would need grammar-specific validation. Neither synthetic project demands naming enforcement; defer it. |
| Nesting or procedure size | No current selector defines these metrics. | odinfmt controls layout, not a procedure-size contract. No equivalent nesting/size contract was established from the surveyed compiler or OLT interfaces. An AST metric or ast-grep-based implementation would need its own proof. Defer without project demand. |

For future size work, define whether the unit is physical lines (including or
excluding comments/blanks), statements, or AST nodes. For nesting, define which
constructs count and whether nested procedures reset the depth. A line limit can
be evaded by compact formatting; AST depth does not measure comprehension.
No such metric is silently selected for this milestone.

## Primary sources and evidence limits

- [Odin overview: require_results](https://odin-lang.org/docs/overview/#require_results)
  documents acknowledgement, including assignment to `_`. The installed
  `odin check -help` also exposes compiler vet/style checks, explicit custom
  attributes and `-disable-non-constant-globals`. The compiler probe above is
  local execution evidence; it establishes one counterexample, not every flag
  interaction or platform.
- [OLS and odinfmt documentation](https://github.com/DanielGavin/ols)
  documents compiler diagnostics, configurable checker arguments and target
  profiles. odinfmt configures width, indentation, braces and other layout.
  The surveyed interface does not establish project-authored AST rules or
  transitive dependency contracts. Formatting remains a separate concern.
- [OLT documentation](https://github.com/RainerXE/odintooling)
  publishes selectable built-in rules, naming options, allocation/error checks,
  JSON/SARIF output and suppressions. These are credible alternatives when a
  project's requirements match the catalog. Configuring built-in rules is
  different from authoring a new arbitrary rule; no such authoring interface
  was established by this survey. Resource-safety claims were not independently
  tested, and are not adopted as guarantees here.
- [ast-grep custom-language support](https://ast-grep.github.io/advanced/custom-language.html)
  describes compiling a Tree-sitter grammar into a dynamic library and
  registering it in project configuration before authoring structural rules.
  This adds grammar distribution and compatibility work. Registration alone
  does not establish Odin semantic resolution or dependency reach. These are
  capability inferences from documentation, not an executed Odin comparison.
- [TigerStyle](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md)
  combines engineering judgment, function-size restrictions, allocation
  constraints, assertions and review expectations. The strict example can
  select explicit state ownership and deliberate error acknowledgement as its
  own choices. A declaration ban does not establish purity; an allocator tag
  does not establish allocation freedom; attribute presence does not establish
  useful error handling. No claim that odx encodes TigerStyle follows.

Revisit extensions when a concrete project supplies a valuable missing contract,
its legitimate counterexamples and acceptable misses. Recheck external tool
behavior before release; moving upstream documentation and this host's compiler
do not constitute cross-version or cross-platform compatibility evidence.
