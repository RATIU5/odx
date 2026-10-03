# odx

@GLOSSARY.md

## Docs

| Path | Holds | Read when | Changed by |
| --- | --- | --- | --- |
| `~/.claude/orchestrate/odx/docs/<feature>-plan.md` | the pstack plan for one feature: `checker-core`, `checker-rules`, `memory-checker` | working on that feature | the Multi-phase plan playbook, approved by the user |
| `~/.claude/orchestrate/odx/docs/<feature>/spec.md` | the earlier behavior contract and its later items; input to that feature's plan until the plan replaces it | writing that feature's plan | nobody; delete once the plan lands |
| `~/.claude/orchestrate/odx/docs/review-2026-09-30.md` | 12 scope-review findings, each with a decision needed | writing the checker plans | nobody |
| `docs/adr/` | hard-to-reverse decisions with reasons; `0004-principles.md` settles conflicts | designing in the area an ADR names, or when goals conflict | agent, with the user's approval |
| `.out-of-scope/` | rejected features and why | a request looks like something odx refuses | agent, with the user's approval |
| `README.md` | the user workflow and dev commands | | user |

- The plan store is local to the user's machine. If it's missing, say so and ask before inferring behavior from code.
- Glossary terms are the vocabulary for code, tests, plans and messages. Adding, renaming or redefining a term needs the user's approval.
- When work contradicts a plan, an ADR or an `.out-of-scope/` entry, say so before going on. When a plan is silent or ambiguous, ask the user.

## Workflow

Use pstack skills only. Don't use skills from `mattpocock/skills` (`grill-with-docs`, `to-spec`, `to-tickets`, `implement`, `triage`, `domain-modeling` and the rest) in this repo.

1. New or changed behavior gets a plan from `/poteto-mode`'s Multi-phase plan playbook, written to the plan store. Settle open questions by prototype or by probing the pinned compiler, and ask the user only about product calls.
2. A contested plan goes through `/interrogate` before execution.
3. Execution starts on the user's go: one plan section at a time, through `/poteto-mode`'s Feature playbook, test-first with `tdd`, golden cases included.
4. Where a playbook says to commit, push, open a PR or merge, stop and hand that step to the user instead.

## Working rules

- `mise tasks` lists the build, test and format commands. The Odin version is pinned in `mise.toml`; core sources are at `$(odin root)`.
- Use the `odin` skill for Odin code, and check core signatures against `$(odin root)`; APIs changed a lot in 2025–2026.
- Verify claims about Odin with the source or a small program, and say which are verified.
- `.gitignore` is an allow-list: new tracked paths need an entry.

## Ending a turn

- Leave committing to the user: after changing files, ask them to commit and give a recommended conventional-commit message for the changes.
- End with one recommended next prompt for the user to send, such as a review of the work just done, an `/interrogate` of a plan, or the next plan section to take on.
