# odx eval — pre-registration

Committed before any recorded run. Plan: [HARNESS.md](../HARNESS.md). Any change after the
first recorded run is an amendment: append it below with its date and reason, never edit
in place. Runs before the recorded run (pipeline debugging, P1) are not analysed for
conclusions.

## Pins

Every result row records all three; rows whose pins differ from these are not pooled.

| Pin | Value |
|---|---|
| Model ID | `________` (fill in and commit before the recorded run) |
| Odin toolchain | `odin version dev-2026-09-nightly:a2fb372` |
| odx commit | the commit containing this file's final version; `-dirty` rows are excluded |
| Effort | `high` (`output_config.effort`), `max_tokens` 32000 |

**Deviation from HARNESS.md §5.** Current Claude models reject `temperature`, `top_p` and
`top_k` (HTTP 400) and the API has no seed. Variance comes from 5 independent samples per
(task, condition); rows record the sample index in place of a seed. No temperature-0 arm.

## Conditions

One runner, one loop; conditions differ only in the switches below (`TRAITS` in
[runner/main.odin](runner/main.odin)).

| | Policy block (system prompt) | odx findings in revision turns | Episodes |
|---|---|---|---|
| C0 | no | no | 1 |
| C1 | yes | no | 1 |
| C2 | no | yes | 1 |
| C3 | yes | yes | 1 |
| C4 | no | no | C0 episodes repeated up to the matched C3 row's spend |

- **Policy block**: the complete output of `odx policy` for the task worktree.
- **Episode**: fresh worktree; one generation turn; then exactly 3 revision turns in every
  condition, whatever the state of the code. Each revision turn contains verbatim
  `odin build` output (every condition), odx findings with each rule's Correction (C2/C3
  only; "none" when empty), and the same fixed instruction to review and reply with the
  complete file. Four model calls per episode.
- **Findings fed back** exclude `odin/*` results: those are compiler output every
  condition already receives, and adding them only to C2/C3 would confound the loop.
- **C4 budget**: `tokens_in + tokens_out` of the C3 row with the same task, sample and
  model. C4 starts episodes until one compiles or cumulative spend reaches the budget,
  and reports the first compiling episode, else the last. Selecting on compilation adds no
  odx signal, because the compiler is available in every condition.

## Metrics

Primary (binary, per row, computed on the final file):
- `compiles`: `odin build task -build-mode:obj` exits 0. No vet flags.
- `tests_pass`: the hidden tests (never shown to the model, added only after the last
  turn) build with `-build-mode:test` and the binary exits 0 within 60 s. A test build that
  fails, e.g. because the signature changed, or a timeout, counts as a failure.
  `tests_pass` is false whenever `compiles` is false.

Secondary: `odx_errors`, `odx_warnings` (non-`odin/*`, non-baselined findings from
`odx check --json` on the final file) as a manipulation check only, never a quality claim;
`tokens_in` (including cache reads and writes), `tokens_out`, `turns`, `episodes`, `wall_ms`,
`edit_applied` (every turn's reply held a parseable ```odin block).

No model-as-judge. Nothing not listed here is reported as an outcome.

## Exclusions

A row with a non-empty `tool_error` is excluded, never scored as a failure. Tool errors:
a compiler or odx crash (nonzero exit with no output, persisting across three attempts),
odx exit 2 or reported tool errors, API or transport failure after curl's retries, a
refusal stop reason, a missing C3 budget row for C4. A paired comparison drops a
(task, sample) pair if either side is excluded. Excluded counts are reported per
condition; if any condition loses more than 5% of rows, that is reported as a threat to
validity next to every result it touches.

Tasks enter the corpus only if the reference solution compiles, passes its tests and is
odx-clean under `--agent reference` for every condition. That gate is fixed before the
recorded run; no task is removed after it.

## Analysis

Unit of inference: the task. Samples of one task are not independent, so the primary
test pairs per-task majority outcomes (true when at least 3 of 5 samples are true).

Comparisons, in this order:
1. **C3 vs C4**: the decision. Primary: exact McNemar on `tests_pass` majority, α = 0.05,
   two-sided.
2. C2 vs C1: loop versus block.
3. C3 vs C0: reported, not led with.
4. C1 vs C0: does the resident block hurt alone.

Comparisons 2–4, and `compiles` for all four, are secondary with Holm correction across
them. For every comparison report the paired difference in per-sample pass rate with a
95% CI from a task-clustered bootstrap (10,000 resamples), plus discordant counts.

Family A (150–200 tasks) is tested as above. Family B (40–60 tasks) is descriptive only:
effect sizes and CIs, no significance claims.

Interpretation follows HARNESS.md §9. A null with a CI inside ±5 pp is reported as
"no effect"; a wider null is reported as underpowered. The conclusion is written whichever
way the result falls.

## Amendments

None.
