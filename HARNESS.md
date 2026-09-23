# odx eval harness — plan

Date: 2026-09-23. Purpose: determine whether odx changes what an LLM produces when writing
Odin, and in which direction. A prior attempt (M6) measured a *regression* in compile and
test rates and was deleted without isolating a cause. This plan exists so the next answer
is decidable.

Nothing else in `DIRECTION.md`, `IDIOM.md`, `LAWS.md` or `APPROACHES.md` is worth building
until this runs.

---

## 1. The question, stated so it can fail

**H1 (correctness).** An agent with odx in the loop produces Odin that compiles and passes
tests at a higher rate than one without, **at equal token budget**.

**H2 (conformance).** An agent with odx in the loop produces fewer odx findings.

**H3 (mechanism).** Any effect is attributable to *findings fed back in a loop*, not to
*policy text resident in context* — and the resident block may be net-harmful.

H2 is nearly tautological (the tool optimises its own score) and is reported as a
**manipulation check**, never as evidence of quality. H1 is the real claim. H3 is what M6
failed to separate and is the reason the design below is factorial rather than A/B.

**Pre-registration.** Write the analysis plan — metrics, conditions, test, exclusion rules
— into `eval/PREREG.md` and commit it *before* the first full run. Analysis chosen after
seeing results is how the prior literature produced its inflated numbers.

---

## 2. Design

Five conditions, same tasks, same model, same seeds, paired.

| # | Condition | Policy block in context | odx findings fed back | Purpose |
|---|---|---|---|---|
| C0 | baseline | no | no | floor |
| C1 | block only | yes | no | isolates instruction-density cost |
| C2 | findings only | no | yes | isolates the loop |
| C3 | both | yes | yes | the shipped configuration |
| C4 | **budget-matched** | no | no | **decides whether odx earns its cost** |

**C4 is the condition that matters and the one everyone skips.** It re-samples C0 with the
same token/turn budget C3 consumed. Olausson et al. showed self-repair frequently *loses*
to plain resampling once you charge for the tokens. If C3 does not beat C4, odx is not
paying for itself regardless of how it compares to C0.

**Every condition runs the same number of revision turns on the same schedule.** In C0/C1/C4
the revision turn happens with no tool output (the agent is simply asked to review and
finalise). This avoids the Huang trap: if revision only fires when findings exist, and
findings correlate with broken code, the gain is an artifact of oracle-guided filtering.

Compiler diagnostics (`odin build`) are available in **all** conditions, including C0.
We are measuring odx, not the compiler. Anything else confounds the two.

---

## 3. Task corpora

No Odin benchmark exists — MultiPL-E contains neither Odin nor Zig. Two families, because
neither alone answers the question.

### Family A — standalone functions (correctness signal)

**Source:** translate HumanEval+MBPP-style problems into Odin, MultiPL-E style.
**Size target: 150–200 tasks.**

Each task is a directory:

```
eval/tasks/a/<id>/
  prompt.md        # natural-language spec, no Odin shown
  signature.odin   # the proc signature the solution must fill
  solution.odin    # reference solution (validation only, never shown)
  test.odin        # @(test) procs, the ground truth
  odx.json5        # minimal policy (roles, a handful of rules)
```

**Validation gate:** a task enters the corpus only if `odin test` passes on the reference
solution and `odx check` is clean on it. A task the reference cannot pass is a broken task,
not a hard one.

**Build method:** translate with an LLM offline, then filter mechanically — this is exactly
MultiPL-T's trick, and the compile-and-test filter is what produces quality without hand
labelling. Expect to discard 30–50%.

**Known limitation, stated up front:** single-function tasks barely exercise the rules odx
actually has. `dependencies/R2` is a whole-graph property and will never fire here. Family A
measures whether odx *harms* correctness; it cannot show odx helps conformance.

### Family B — repo-situated edits (conformance signal)

**Size target: 40–60 tasks.** Fewer, more expensive, and the only place odx's real rules
apply.

Built from a seed Odin project (the `examples/policies/strict` tree extended, or a small
purpose-built app) with roles, import boundaries and an error policy. Each task is a feature
request or bug fix requiring edits across 1–3 packages, with tests.

```
eval/tasks/b/<id>/
  repo/            # git worktree of the seed project at a fixed commit
  prompt.md        # the change requested
  test.odin        # added tests that must pass
  expect.md        # which rules a naive implementation would violate
```

`expect.md` is the point: each Family B task is designed so the obvious implementation
crosses a role boundary, drops an allocator, or omits `@(require_results)`. This is where
H2 becomes meaningful.

---

## 4. Metrics

**Primary (hard, mechanical, pre-registered):**
- `compiles` — `odin build` exit 0
- `tests_pass` — `odin test` exit 0, all tests

**Secondary:**
- `odx_errors`, `odx_warnings` — counts from `odx check --json` (manipulation check)
- `tokens_in`, `tokens_out`, `turns`, `wall_ms` — for the C4 budget match
- `edit_applied` — did the agent's patch apply cleanly

**Explicitly excluded: LLM-as-judge.** Position bias, self-preference bias and prompt
sensitivity are all documented, and a judge would share the style preference under test.
Style quality is not measured. If it cannot be measured mechanically, it does not appear.

---

## 5. Protocol

Per (task, condition, sample):

1. Fresh worktree from the task's fixed commit.
2. Build the prompt: spec + (policy block if C1/C3).
3. Agent generates. Write files.
4. **Fixed loop, max 3 iterations** (returns are marginal past 3–4 in the published data):
   - `odin build` → on failure, feed verbatim diagnostics back
   - if C2/C3: `odx check --json` → feed findings back, including each rule's `Correction`
   - if C0/C1/C4: an equivalent-cost revision turn with no tool output
5. Final: record all metrics.
6. Discard the worktree.

**Determinism controls:** pin the model ID, fix temperature (run at both 0.0 and a sampling
temperature — 0.0 alone understates variance), fix seeds per (task, sample), pin the Odin
toolchain and the odx commit. Record all of it in the result row.

**Samples:** 5 per (task, condition). Task-level variance dominates, so samples reduce noise
but do not substitute for task count.

**Result format:** one JSONL row per run, into `eval/results/<run-id>.jsonl`. Nothing
aggregates at write time; analysis is a separate pass over raw rows.

---

## 6. Analysis

**Paired McNemar** on the binary outcomes (compiles, tests_pass), per condition pair. The
comparisons that matter, in order:

1. **C3 vs C4** — does odx beat spending the same budget on resampling? *The decision.*
2. **C2 vs C1** — is the loop or the block responsible? *The M6 post-mortem.*
3. C3 vs C0 — the naive comparison everyone reports. Report it, don't lead with it.
4. C1 vs C0 — does the resident block hurt on its own? *Directly tests the instruction-
   density hypothesis.*

**Power.** Detecting a 10pp difference at ~25% discordance needs ~200 paired tasks at 80%
power; 5pp needs ~600. Family A at 150–200 tasks can detect ~10pp. **Family B at 40–60
cannot detect anything under ~25pp** — report it as descriptive, with effect sizes and CIs,
not as a significance test. Say so in the write-up rather than over-claiming.

**Report confidence intervals always.** A null result with a tight CI is a real finding; a
null with a wide CI means the experiment was too small.

---

## 7. Build plan

| Phase | Work | Effort |
|---|---|---|
| **P0** | Runner skeleton: task loader, worktree management, agent invocation, JSONL writer, metric collection. Shell + a small Odin or Python driver. No framework. | 1–2 days |
| **P1** | 20 Family A tasks, hand-checked. Run all 5 conditions end to end. **Goal is a working pipeline, not a result** — 20 tasks detects nothing below ~25pp. | 1–2 days |
| **P2** | Scale Family A to 150–200 via LLM translation + compile/test filter. | 2–3 days, mostly unattended |
| **P3** | Seed project + 40–60 Family B tasks with `expect.md`. The expensive, hand-made part. | 3–5 days |
| **P4** | Analysis script: McNemar, CIs, per-condition tables. Pre-register before running. | 1 day |
| **P5** | Full run, all conditions, 5 samples. | hours of wall time, real API cost |

**Total: roughly two weeks of focused work.** P0–P2 alone (about a week) answers H1 and H3,
which are the questions that actually block everything else. P3 can follow.

**Cost:** 200 tasks × 5 conditions × 5 samples × ~4 turns ≈ 20k model calls. Budget
accordingly; consider a cheaper model for pipeline debugging and the real model only for the
recorded run. Record the model in every row — the low-resource literature is explicit that
the optimal intervention differs by model size, so a result for one model is not a result
for all.

---

## 8. Guards against known failure modes

- **Oracle-guided filtering** (Huang): revision fires on the same schedule in every
  condition. Already in §5 step 4.
- **Budget confound** (Olausson): C4 exists. Do not report C3 vs C0 without it.
- **Goodhart**: `odx_errors` is a manipulation check. It is not allowed in the abstract as
  a quality claim.
- **Analysis-after-the-fact**: `eval/PREREG.md`, committed first.
- **Task contamination**: HumanEval-derived tasks may be memorised. Note it; Family B is
  purpose-built and is the uncontaminated arm.
- **Flaky infrastructure**: the pinned toolchain segfaults intermittently (the existing 3×
  retry loops in `odincheck.odin`). Record tool errors separately and exclude those runs
  explicitly rather than scoring them as failures.

---

## 9. What each outcome means

| Result | Reading | Action |
|---|---|---|
| **C3 > C4 on tests_pass** | odx earns its budget | build out §5 of `APPROACHES.md` — applicability, fix-as-data, exemplars |
| **C3 ≈ C4, C3 > C0** | odx works, but so does resampling | keep odx for conformance; stop claiming correctness gains |
| **C2 > C1** | the loop helps, the block hurts | shrink the resident block, move to on-demand per-file constraints |
| **C1 < C0** | the policy block is net-harmful | this was M6's likely cause; cut or drastically shrink it |
| **All null, tight CIs** | odx does not change LLM output | honest answer: odx is a CI linter for humans. Smaller product, still real |
| **All null, wide CIs** | underpowered | more tasks, not more conclusions |

The fifth row is a live possibility and the plan is written so it is reportable rather than
embarrassing. An honest null is worth more than four more documents of speculation.
