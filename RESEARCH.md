# Research findings: odx and LLM-written Odin

Date: 2026-09-23. Condensed from four research passes (fallow.tools, Odin toolchain and
community, Ginger Bill's writing, rule induction, specification mining, LLM capability,
rule representation, generation- and post-generation techniques, niche-language ecosystems)
plus a measurement of the Odin stdlib as a mining corpus.

This file holds **durable findings with citations**. The plan lives in `ROADMAP.md`; the
experiment that decides it lives in `HARNESS.md`. Retire this file once its conclusions are
absorbed, as the earlier milestone research docs were.

---

## 1. The thesis, and its honest status

odx's value proposition is: **a constraint oracle — what an agent consults before writing
Odin, and what proves compliance after.** The compiler owns "is this legal Odin"; nothing
owns "is this legal *here*".

**Status: unproven, and one prior measurement was negative.** The deleted M6 harness showed
odx *regressed* agent compile and test rates. Two mechanisms independently predict that
result, so it is expected rather than anomalous:

- **Instruction density.** Reliable instruction-following breaks down past **5–6
  simultaneous constraints**, and for **12 of 15 models at 3 or fewer**
  (arXiv:2608.12426, ~370k deterministic checks). IFScale (arXiv:2507.11538) finds 68%
  accuracy at maximum density with a documented primacy bias. A generated policy block
  listing every rule is past the cliff by construction.
- **Proxy-signal repair.** Olausson et al. (ICLR 2024, arXiv:2306.09896) show self-repair
  frequently *loses* a budget-matched comparison against plain resampling, and isolate
  feedback quality as the bottleneck.

**The honest ceiling on the claim.** The strongest pro-static-analysis result
(arXiv:2508.14419) drove findings from >40% to 13% — but every improved metric was *the
analyzer's own output*. odx can demonstrate **conformance improves**; it cannot infer **the
code got better** without a budget-matched control.

**There is no rigorous evidence that CLAUDE.md-style files improve code quality.** The one
solid study (arXiv:2601.20404, 124 real PRs) measures efficiency: −28.6% runtime, −16.6%
tokens, completion *"comparable."*

---

## 2. Community and ecosystem reality

**Demand for an Odin policy tool is near-zero, measured.** GitHub search on `odin-lang/Odin`
for `"lint"` returns **4 results ever**, none a request. No forum thread or issue asks for
one. `vet` appears in 62 issue titles — **new checks in this ecosystem arrive as compiler
flags.** The word "linter" appears in-community as an insult.

**The decisive data point:** `olt` (RainerXE/odintooling) is a 30-rule Odin static analyzer
with SARIF, suppressions, an LSP proxy **and an MCP server for Claude Code**. Shipped July
2026. **Four GitHub stars**, zero forum mentions. It already built three things an
adoption-driven plan would recommend, and nobody cared.

**Standing risk:** `allocators/R1` exists only because there is no `-vet-explicit-allocators`
flag — and forum t/1642 is a user asking for exactly that flag. Every rule the compiler
could absorb is a depreciating asset.

**Zig has ceded this surface deliberately.** Its code of conduct bans LLM-generated content
outright (*"No LLMs for finding bugs"*); maintainers may reject on suspicion; Bun forked
rather than upstream a 4× perf gain. Zig ships no structured diagnostics (issue #16376 open).
**An Odin ecosystem shipping machine-consumable diagnostics would be ahead of Zig, not
catching up.** Odin currently has Zig's attitude without Zig's written policy.

**Elixir is the only small ecosystem doing this seriously** — and the structural lesson is
that **ExDoc emits `llms.txt` by default**. They changed the doc generator rather than
convincing 10,000 authors. `usage_rules` was adopted because it reduced *maintainer* support
load from hallucination-driven questions, not to "help the AI."

**Ginger Bill's positions that bind:**
- *"Nudging over prohibition"* is his named philosophy: *"never outright prevent people from
  bypassing them. Let people disable the safety and shoot the gun if they need to."*
  → validates read-only checks, reason-bearing suppressions, visible baselines; **invalidates
  a commit-blocking gate.**
- *"`core:foo/bar` does not need to import `core:foo`"* — **nesting does not imply
  dependency**, so layering must come from explicit config, never path position.
- *"'Highly configurable' is often just an excuse for shipping no opinion at all."*
  → `examples/policies/` must carry the opinion; they are currently underweighted.
- He says **nothing** about `@(require_results)`. What he does name is sharper than what
  `errors/R3` checks: errors degenerating into *"a fancy boolean"* passed up the stack.

---

## 3. What the compiler already owns

Verified against `dev-2026-09-nightly:a2fb372`. Never rebuild: unused vars/imports/procs,
shadowing, cast/transmute, semicolons, trailing commas, tabs, brace style, switch-case column
(`-vet-*`, `-strict-style`); machine-readable diagnostics (`-json-errors`); per-package
scoping (`-vet-packages`, `#+vet` tags); the entity table (`odin doc -doc-format` +
`core:odin/doc-format`); the AST (`core:odin/parser`); a DOT import graph
(`-show-import-graph`); test results as JSON (`ODIN_TEST_JSON_REPORT`); dead exports
(`-show-unused-with-location`).

Genuinely absent ecosystem-wide, and therefore odx's legitimate territory: rule IDs and
stable finding identity; baselines and a suppression ledger; architectural policy over the
import graph; attribute-*presence* policy; project-wide `explicit-allocators`; a project
manifest and role model; SARIF; complexity metrics.

---

## 4. Rules from examples, and rules from the corpus

**Both mining proposals were assessed. Both fail as statistics and survive as hypothesis
generation.**

**From paired examples** (edit-pattern mining via anti-unification): Revisar needed
**288,899 AST edits to yield 89 curated rules**; Getafix's 1,268 fixes worked only because
they were pre-sorted into six categories (~200 near-identical each). Fifty heterogeneous
pairs gives one example per pattern, and the generalization of a singleton is the singleton.

**From the stdlib** (specification mining / deviant-behavior analysis): independent
evaluation of every static API-misuse detector on MUBench found **0.0%–11.4% precision**
(GrouMiner 0.0%, DMMC 9.9%, JADET 10.3%, Tikanga 11.4%). PR-Miner: 27% on Linux, **10% on
PostgreSQL**. Over half of all false positives were *"the minority was actually correct"*
(34.3% legitimate-rare-usage + 19.2% equally-valid-alternative).

**The corpus was measured and does not support global mining:**

- **63% of the distribution must be excluded.** `core/rexcode` alone is **39% of core's
  lines, 66% of all procedures, 94.4% near-duplicate generated boilerplate**. Plus `vendor/`
  (8 procs in 140k lines take an allocator) and `core/sys`. Remainder: **~255k lines** —
  below the PostgreSQL data point.
- **13% of the corpus is platform-conditional** (74 stem groups, 220 variant files), so
  support counts inflate 3–10× without deduplication.
- **Measured adherence:** `or_return` over `if err != nil` **~87%** (6.4:1, the only strong
  signal); `Error` enum `None`-first **85.4%**; `make`/`new` ⇒ allocator param **75.7%**;
  final `Allocator_Error` ⇒ directive **29.6%**; allocator ⇒ `loc` **24.6%**;
  trailing bool ⇒ `#optional_ok` **6.5%**. **Nothing reaches 99%.**
- The allocator/`loc` law is **100% in `core/bytes`, 78–97% in `slice`/`strings`/`mem`/
  `runtime`, and 0% in `text`, `net`, `crypto`, `image`, `time`, `fmt`.** Bimodal.
- **The counterexamples are principled.** The largest violation cluster is
  `core/odin/parser`, which carries the allocator on the `^Parser` struct — a legitimate
  design choice no syntactic miner can distinguish from an omission.

**What survives:**

1. **Prefer contradiction over deviation.** Engler's statistical checkers were his worst
   (16–32% FP); his MUST-belief checkers hit 3.8% because internal contradictions need no
   corpus and no threshold. *"Takes an `allocator` and doesn't forward it to `make`"* is a
   contradiction within one procedure — its adherence rate is irrelevant. **This shape is
   the target; frequency-derived style rules are not.**
2. **Mine per-package against named exemplars**, never globally — which is just the existing
   `roles` model.
3. **The LLM proposes a predicate; an AST query supplies every number.** RULER
   (arXiv:2404.06654) tests this as its *aggregation* category and finds aggregation degrades
   first as context grows; counting failures are architectural (arXiv:2412.18626).
4. **A validator is non-negotiable.** SpecGen: 35.95% raw → **59.97%** with OpenJML in the
   loop. KNighter (SOSP 2025) validated each synthesized checker against its originating
   patch and found 92 latent Linux bugs, 30 CVEs. **odx already owns this**: the
   `fires`/`silent` blocks checked bidirectionally in CI are exactly that contract.
5. **Dedup platform variants before counting.** Le Goues & Weimer went from 99% FP to **5%**
   purely by weighting the corpus rather than counting all sites equally.

**Expected yield**, from the papers' ratios (Revisar 493→89, KNighter 61→39→37): a few
hundred candidates, **a few dozen shippable**, 5–15 min human triage each.

**"Law" is the wrong word.** Tier 1 *Regularity* (a measurement, all mining produces),
Tier 2 *Enforced convention* (declared by a human, decided by a procedure), Tier 3 *Law*
(entailed by semantics). Mining cannot promote Tier 1 → Tier 2, because promotion is
precisely the act of asserting the exceptions are errors rather than the rule being wrong.

---

## 5. What is syntactically detectable

**High-value and reliably syntactic:** allocator parameter taken but not forwarded to
`make`/`delete` in the body; `if err != nil { return ..., err }` → `or_return`; `[dynamic]T`
parameter never grown; empty default case → `#partial switch`; missing `#optional_ok` /
`#shared_nil`; `Error` enum whose first member isn't `None`; `mem.alloc(size_of(T))` →
`new(T)`; `using` as statement or parameter.

**Needs dataflow — do not attempt:** does this allocation leak; does a temp value escape
`free_all`; does this allocator match that `delete`. *This is everything that matters most
about memory correctness.*

**Judgment only — keep as reviewer advice:** is `bool` adequate; is SoA right; is this
abstraction earned. Promoting `#soa`/`distinct`/`bit_set` preferences to mechanical rules
produces mostly false positives.

---

## 6. Engine capability

The whole rule engine is under 1,200 lines (`check_contract.odin`, `pattern.odin`,
`checks.odin`, `topics.odin`).

**Procedure bodies are reachable**: `call` and `if` use `ast.walk` and descend into them
(`checks.odin:312`, `pattern.odin:205`). Only `import`/`foreign`/`decl`/`proc` are
package-scope-only via `package_declarations` (`pattern.odin:104-123`).

**Class A (cheap):** one node class narrowed by a local property, including inside bodies —
a `CHECK_SHAPES` row, a validator arm, a visitor case. `at:` already carries the comment
`"package_scope" (the only scope today)` — a planted seam.

**Class B (new subsystem):** relating two nodes. `ast.Visitor` passes only `(v, n)` so no
parent stack exists; every matcher reports inline; `Check_Spec` is a flat field bag that
cannot nest.

**But universal rules invert to existential violations** — "every `make` forwards the
allocator" becomes "some `make` inside an allocator-taking proc lacks it." This is how
Semgrep, ast-grep and Coccinelle all avoid `forall` machinery, and it moves the most
valuable rule into Class A.

**Odin's block-scoped `defer` dodges the hardest problem.** Coccinelle's `alloc_free.cocci`
needs **five `when !=` clauses** plus an explicit path quantifier and still ships rated
*"Confidence: Moderate"* — all to reconstruct scope C doesn't have. A `same_block` rule in
Odin is simpler *and* more accurate.

**IR additions, if needed:** relational predicates (`inside`/`has`/`follows`) each with a
mandatory `stop_by` bound — the highest-leverage FP control in the survey; `all`/`any`/`not`
with `not` restricted to metavariables bound by a sibling positive predicate, enforced at
load time. **Do not build a metavariable template language**: Refaster needed four escape
hatches within a few years and still cannot express either motivating rule.
`pattern.odin:10` already says to wait for a written-down failing case.

**Architecture:** one parse per file, group rules by node kind, one walk, plus a keyword
prefilter. That index is why Coccinelle survives 16.5M LOC. `check_calls` batching is the
instinct to generalise.

**The standing warning:** `errors/R5` was retired because *"the mechanical predicate encoded
a different rule"* than the intent. Expressiveness is not the binding constraint;
predicate/intent fidelity is. Bend 2 hit the same wall — Taelin: *"Laws only protect what
you remember to write. They're not a silver bullet."*

---

## 7. Delivery: how findings reach a model

**Docs-in-context is a small lever.** *No Resource, No Benchmarks, No Problem?*
(arXiv:2606.16827) on Gleam as a no-resource language: RAG over documentation moves pass@1
**0.5% → ~2%**; continued pre-training is worth **~20–25 points**. The entire
llms.txt/AGENTS.md/rules-file strategy operates on the 1–2 point lever.

**But that benchmark is single-shot with no compiler in the loop.** The iterative regime odx
occupies is **unmeasured in the literature** — simultaneously the caveat against
context-stuffing and the opening for an original contribution. **MultiPL-E contains no Odin
and no Zig**; no benchmark number exists for either.

**Fix-as-data is the strongest delivery mechanism.** Rust's `--error-format=json` carries
`suggested_replacement` plus an **`applicability`** field (`MachineApplicable`,
`MaybeIncorrect`, `HasPlaceholders`, `Unspecified`) — that field is why `cargo fix` applies
suggestions **with no model in the loop**. SARIF standardizes it (`result.fixes`); GitHub's
one-click apply consumes it. **A fix-as-data payload consumes zero instruction slots** — it
is not an instruction, which is the cleanest answer to §1's density problem.

**Rewriting works only where it is total.** Cox's actual gofmt argument is *"once you have a
tool that can parse and print a program losslessly, it's easy to insert mechanical processing
in the middle"* — **gofmt exists so `go fix` can exist.** Every successful autofix ecosystem
is narrow: Coccinelle has **59 semantic patches in-tree after a decade**; `go fix` has 22
analyzers; Refaster scored **0%** on a library migration because it cannot touch signatures;
OpenRewrite autonomous scored **7.0% across 228 repos**. Refactoring engines with full type
information still produced **518 documented bugs** across Eclipse/IntelliJ/NetBeans.

**Fix triage for odx's rules:** safe — `#partial switch`; `@(require_results)` is
*safe-but-cascading* (emit the whole call-site cascade or nothing). Unsafe, flag-only —
`or_return` conversion, valid only when the error-branch return values are exactly the zero
values `or_return` produces. **Never — adding an `allocator` parameter** (signature change,
and auto-filling `context.allocator` defeats the rule) **or `defer delete`** (a
use-after-free generator when the value escapes; converts a leak a sanitizer catches into
corruption it does not).

**Generation-time options assessed:** grammar-constrained decoding is **blocked** —
Anthropic's structured outputs are JSON Schema only, no CFG, no `logit_bias`; OpenAI's Lark
grammars are documented as unreliable for complex grammars. Local models make it real
(SynCode: 96% syntax-error reduction) but trade away the semantic competence that is the
actual bottleneck, and Grammar-Aligned Decoding (arXiv:2405.21047) shows per-token masking
does not sample the grammar-conditioned distribution. **Fine-tuning** needs validated
instruction pairs, not raw LOC, and yields a weaker model. **What applies:**
compiler-in-the-loop (a compiler diagnostic is the external ground-truth feedback Olausson
says rescues the loop) and **certified exemplar retrieval** — RepoCoder reports 23.32% →
42.63% over two iterations, and `odx check` can certify the exemplar pool is rule-clean,
which is a better selector than any published heuristic.

**Rules say what to avoid; exemplars say what to produce.** For a low-resource language the
model may have no correct prior for the compliant form.

---

## 8. Governance, from the only rule sets that survived

- Google's Tricorder gates every check at **<10% *effective* false positives**, where an
  effective FP is one *the developer did not act on* — measured behaviourally, not logically.
  Their actual rate is just under 5%.
- Linux's `.cocci` files each carry `// Confidence: Low|Moderate|High`, filterable by the
  runner.
- Neither project has a rule-*deprecation* story. If odx wants one it must be designed in:
  per-rule fire counts in the baseline, and a "fired zero times in N runs" report.

---

## 9. Adjacent work

**Bend 2** (released 2026-09-17) is convergent evolution: `LAWS.bend` declares invariants and
the compiler demands a machine-checked proof. Its own framing is *"`LAWS.bend` is `AGENTS.md`
backed by proof."* It **complements rather than competes** — it proves semantic invariants
you formalize and has **no linter, no style checker, no dependency tooling** (its LSP is
*"formatting-only… intentionally exposes no diagnostics"*). Cautionary: its flagship demo
needs 58 lines of laws plus **442 lines of hand-written proof** where ~40 lines of SPARK/Ada
discharge the same properties automatically; its 22.5k stars are *inherited* from Bend 1's
renamed repo; contributors are essentially one person; no production use.

**fallow.tools** (TypeScript) solved agent integration, not analysis. Transferable: a
pre-edit constraint query, typed JSON contracts, `actions[]` marking auto-fixable findings,
stable fingerprints. Not transferable: its commit-blocking hook (violates the escape-hatch
principle in §2), and its analysis surface (dupes, health scores, similarity) is a different
product.
