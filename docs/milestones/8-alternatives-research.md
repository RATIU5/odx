# Milestone 8 alternatives and agent-evidence review

Research date: 2026-09-21, macOS arm64. This is a fresh primary-source review
and bounded local comparison, not an ecosystem-wide superiority claim. No agent
productivity experiment was run. The decision remains conditional on milestone
8's separate real-project and release-validation results.

## Current capabilities and equivalent requirements

The comparison uses the committed minimal policy's two requirements—no mutable
package declarations, including inactive branches, and no direct foreign
declarations—and the strict policy's added role-specific transitive dependency
restrictions, selected result attributes, and allocator file tags. Formatting,
compilation, and runtime safety are separate requirements.

| Tool | Current primary-source evidence | Equivalent-policy assessment |
| --- | --- | --- |
| Odin compiler | The current compiler source lists structured diagnostics, compiler vet flags, warning controls, dependency exports, and nonconstant-global restrictions. Local `odin help check` confirms these on `dev-2026-09:a2fb372b7`. [Compiler source](https://github.com/odin-lang/Odin/blob/master/src/main.cpp) | Owns compilation, attribute semantics, and allocator vet behavior. It does not make arbitrary project conventions compiler errors. In particular, its nonconstant-global flag is narrower than the minimal policy, as reproduced below. |
| OLS / odinfmt | Published OLS options include parser diagnostics, compiler checking with `checker_args`, target profiles, and formatting through odinfmt. Formatter settings cover indentation, braces, width, and imports. [OLS README](https://github.com/DanielGavin/ols/blob/master/README.md) | Appropriate for editing, formatting, and compiler feedback. No equivalent local structural-rule or role/dependency policy authoring interface was found in this documented configuration. Absence from documentation is not a proof of impossibility. |
| OLT / odintooling | Publishes configurable built-in checks, naming and resource/error diagnostics, inline suppression, JSON/SARIF output, an LSP proxy, and an MCP interface. It publishes symbol graph export and caller/impact queries. [OLT README](https://github.com/RainerXE/odintooling) | A real neighboring analyzer. Its discarded-error and FFI resource checks answer different questions from requiring a selected API attribute or forbidding direct foreign declarations. No equivalent role/transitive-import contract or general local rule-authoring interface was found in the reviewed public configuration. |
| ast-grep | Supports project-authored structural YAML rules and custom languages through a compiled Tree-sitter library registered in `sgconfig.yml`. [Custom language support](https://ast-grep.github.io/advanced/custom-language.html), [rule configuration](https://ast-grep.github.io/reference/yaml) | Credible for the minimal source restrictions, with correctly scoped grammar-specific rules and parser coverage checks. The strict policy's resolved result classification and transitive graph require additional analysis. Its FAQ expressly excludes type and control/data-flow information. [Analysis limits](https://ast-grep.github.io/advanced/faq.html) |

OLT was reviewed through its live primary documentation, not executed: no `olt`
binary was found on PATH. Its advertised resource-safety behavior was not
independently validated, nor is a published graph feature proof that it enforces
odx's precise deny policy. No unsupported “odx is unique” claim follows.

The web references above were reopened during this milestone. They are live
branch references, not release pins; published features may differ from installed
versions. The actual locally executed versions and pinned grammar are below.

## Local counterexamples and observed tool behavior

The installed compiler reports `/opt/homebrew/bin/odin version
dev-2026-09:a2fb372b7`. Fresh temporary files demonstrated:

```odin
package probe
count: int
value := 7
```

`odin check <file> -file -no-entry-point -disable-non-constant-globals` exits 0.
Both declarations remain mutable, so accepting them is a counterexample to
equating the flag with “no mutable package declarations.” Separate files with
`when false { count: int }` and `foreign import libc "system:c"` also compile
with that flag. `odinfmt <file>` exits 0 and preserves those declarations while
formatting. These positive compiler/formatter results are expected, not bugs:
the project restriction is deliberately stronger and different.

Installed ast-grep is `0.45.1`. The previously checked-out Odin grammar is pinned
at `d2ca8efb4487e156a60d5bd6db2598b872629403`. Its
[primary repository](https://github.com/tree-sitter-grammars/tree-sitter-odin)
was rechecked, but this experiment does not claim the pinned grammar is the
latest available revision. The existing compiled grammar and custom-language
configuration were reused to repeat the committed
[milestone 1 comparison](1-alternatives-research.md):

- The compiler-valid probe still compiles under the installed compiler.
- `ast-grep run --lang odin --kind ERROR --json=compact probe.odin` still reports
  two grammar error nodes around the valid anonymous procedure-field struct.
- `foreign_block` finds its separate foreign block. `import_declaration` finds
  two ordinary imports and the foreign import; a minimal-policy implementation
  must discriminate the latter rather than banning all imports.
- The malformed probe returns an `ERROR` match with command exit 0. A successful
  structural search is not a completeness or compilation certificate.

Commands used the pinned checkout's explicit `--config` path. These repetitions
establish concrete integration costs and grammar disagreement on the pinned
configuration; they do not show that current Tree-sitter releases are universally
unsuitable. OLS was not exercised as an editor session; only its documented
interface and the installed formatter were reviewed.

## Existing agent pilot: what is actually supported

The raw rows remain in `git show 7de8f3a:README.md`. Re-summing the first 30 rows
reproduces the public totals exactly:

| Condition | Compiled | Tests passed | Policy findings | Turns | Seconds |
| --- | --- | --- | --- | --- | --- |
| bare | 10/10 | 9/10 | 18 | 71 | 274 |
| for | 8/10 | 7/10 | 4 | 66 | 407 |
| hook | 8/10 | 7/10 | 0 | 104 | 349 |

Six additional rows reran only `ring` and `stack`; both passed under all three
conditions. That is evidence of variability, not proof that the original failures
were noise, proof of harm, or proof of benefit. The observed hook turn difference
is 46.5%; no causal productivity estimate follows from that arithmetic.

The removed harness is inspectable at `git show 7de8f3a^:odx/eval.odin`. It runs
conditions in a fixed order, invokes `claude -p` without an explicit model pin,
and records turns and integer elapsed seconds. It excludes unfinished sessions
from rows by failing early. It configures a Stop hook only; the README's
“edit + stop hooks” label is not supported by that retained harness. Historical
settings outside the harness were not reconstructed. Its zero-finding hook
result is entangled with the stopping condition, and the harness's policy
scoring is not an independent quality measure. The selected reruns and tiny task
sample do not address ordering effects or reproducibility. Tool versions,
token/tool-call overhead, task difficulty calibration, and independent task
completion assessments are not established by the surviving rows.

Suggested public wording:

> An earlier ten-task pilot compared no odx, policy text in the prompt, and a
> Stop-hook condition. Initial compile/test outcomes were lower under the odx
> conditions; selective reruns of two failing tasks passed in all conditions.
> The small, nonrandomized pilot is inconclusive and does not establish an
> effect on productivity or correctness. Current odx provides optional guidance
> and advisory feedback; no AI-productivity benefit is claimed.

No new agent experiment is justified for this release decision. A future study
needs an explicit benefit hypothesis, prespecified success and resource budgets,
pinned model/tool versions, randomized or balanced order, repeated complete
trials, all failures/retries retained, and separate scores for policy compliance,
compilation, tests, completion, elapsed time, turns, and tool/token overhead.

## Alternatives, release recommendation, and limits

| Approach | Benefit | Cost / decision |
| --- | --- | --- |
| Keep native structural checks plus narrow compiler evidence | Fits the two demonstrated policies; current compiler AST and tested coverage contracts avoid a second parser distribution. | Selector maintenance and compiler compatibility remain odx responsibilities. Preferred experimental scope if real-project and full-CI gates pass. |
| Replace custom checks with compiler/formatter/OLT coordination | Reuses established tooling and may meet projects needing only their existing diagnostics. | The compared project contracts are not established as equivalent; replacing them now would lose requested behavior or require additional glue. Preserve these tools as complements. |
| Adopt ast-grep as the policy backend | Rich reusable structural patterns and lint-rule authoring. | Needs pinned grammar distribution, disagreement handling, and separate compiler/graph logic. Current evidence does not justify replacing the native backend. |
| Defer broad release and collect focused user feedback | Honest about usability and platform uncertainty. | Slower adoption; appropriate if real-project budgets or validation fail. |

Recommend, at most, a narrow experimental release on the validated toolchain and
host. Release language should distinguish enforced syntax and bounded graph facts,
configured project choices, heuristic error classification when enabled, and
review-only guidance. No runtime purity, allocation freedom, all-path cleanup,
all-platform support, universal grammar correctness, or agent-productivity claim
is supported. This alternatives review does not replace the real-project latency,
false-positive, authoring-cost, and maintenance evidence or fresh CI required by
the final release record.
