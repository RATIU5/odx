# Milestone 7 obsolete setup and compatibility research

Research preceded implementation; completed changes are recorded below. Rechecked current sources, public CLI,
local M6 policy examples, and pinned Odin `dev-2026-09-nightly:a2fb372` on macOS.
The bounded compiler probe ran 20 checks and 20 doc exports; this is not a
compiler reliability study.

## Proven removal candidate

`cmd_init` appends `.odx/cache/` to an existing `.gitignore`, but repository searches
find no cache reader, writer, directory creation, invalidation or cache setting.
The M2 graph and M4 guidance records explicitly chose uncached computation. A fresh
scratch directory with `.gitignore` containing `build/\n` reproduced:

- `odx init --root <scratch>` exits 0.
- `.gitignore` becomes `build/\n\n.odx/cache/\n`.
- No `.odx/cache` directory exists.

Remove that append block and the repository's unused `.gitignore` cache entry.
This stops an unrelated write and removes misleading setup. Do not edit existing
users' ignore files: harmless legacy entries are their files. No command/field
removal is needed. Test init preserves an existing ignore file byte-for-byte and
still writes its actual requested configuration. Existing setups continue to
work because no runtime cache uses the entry. Reintroduce caching only after
measured demand and explicit invalidation semantics.

## Documentation fields are not obsolete behavior

| Surface | Actual consumer | Decision |
| --- | --- | --- |
| `why`, `instead_of`, `evidence`, `cost` | Required authoring metadata; `explain` prints all four. Why and instead_of also appear in findings/guidance. | Retain; documentation-only does not mean unused. |
| `statement`, `fix_hint`, fires/silent | Diagnostics, guidance and executable rule examples | Retain; no duplicate field deletion justified. |
| `role` | Scratch execution context for `rule test`; independent of check roles | Retain; M6 corrected effective configuration behavior. Clarify context if needed. |
| Topic prose, applies_to roles | Scoped reviewer advice and compiled examples | Retain; advice is intentionally not mechanically enforced. |
| `class` | Structured diagnostics and legacy identity-related consumers | Retain public field; no evidence supports removal. |
| `blocking` | Schema-1 compatibility output, explicitly separate from exit decisions | Retain pending versioned compatibility change, irrespective of implementation utility. |
| `odin.declined` | Doctor validates explanations and emits configured flag decisions | Retain; it is operational configuration. |

The current scaffold's `evidence` commentary insists on a compiler command that
shows a failure, but source-policy predicates can deliberately reject
compiler-valid syntax. Rewrite that authoring instruction around reproducible
compiler/source evidence and bounded matching examples. Do not weaken required
nonempty metadata merely to shorten files; its maintenance burden is not shown to
outweigh authoring value.

## Public selectors and stale comments are separate inventories

`path_role`, `banned_import`, `vet_tag`, `require_attribute` and pattern selectors
remain validated public contracts. Pattern call, import, proc, decl and foreign
have implementations and contract tests. M6's project-owned rules actively use
decl and foreign behavior independently of built-ins; earlier contract tests
exercise the public call and proc selectors. Keep all of
these; absence from the built-in catalog is not evidence of dead code.

Specific stale comments suitable for a narrow comment-only pass:

- `topics.odin`: “Every kind runs and every finding blocks” contradicts disabled,
  inapplicable and unavailable checks, warning exit behavior and baselines.
- `topics.odin`: call selector names described as “canonical pkg.name” overstates
  syntactic spelling as resolved identity; alias/shadowing boundaries are public.
- `checks.odin`: batched call traversal described as O(files), despite traversing
  nodes and evaluating rules. State the concrete benefit (one AST walk per file),
  avoiding an unsupported complexity claim.
- `rule_cmd.odin`: compiler-failure-only evidence comments conflict with valid
  project source restrictions as discussed above.

Historical retirement statements use names such as M7, M8.3 and CUT_IMPR Stage 4
from earlier work, not this roadmap. Keep retired IDs and their reasons for
compatibility; if touching their prose, remove ambiguous historical labels or
explicitly distinguish the earlier plan. Do not revive or delete IDs merely to
align numbering. Those rule statements are product metadata, not code comments.

No broad comment deletion is supported by this audit. Parent invoked the
comment-cleanup skill; implementation should read its exact instructions, limit
the separate comment pass to touched files, and record kept/deleted/rewritten
counts. Preserve concrete workaround context below.

## Compiler retry revalidation

The current wrappers retry a successfully started compiler at most three times
only when it exits nonzero with empty stderr. Explained failures do not retry;
persistent failures produce tool errors and unavailable evidence. This applies
to `odin check` and `odin doc`.

Probe package imported `core:fmt` and exercised a format string. Each check used
`odin check <package> -no-entry-point -json-errors`; each export used
`odin doc <package> -doc-format -out:<temporary-file>`. No `-thread-count:1` was
supplied, so the test exercised default threaded invocation. Results:

| Command | Runs | Exit 0, empty stderr | Crashes observed |
| --- | --- | --- | --- |
| check | 20 | 20 | 0 |
| doc | 20 | 20 | 0 |

Earlier M1 research recorded intermittent threaded failures. Forty successful
small runs do not disprove that failure mode. Retain bounded retries and their
failure reporting. Removing them saves little successful-run cost and risks
reintroducing false tool failures. Revisit with a compiler update, known upstream
fix and representative stress evidence. This research does not claim a crash was
reproduced or that retries guarantee successful evidence collection.

## Format substitution revalidation

`rule_add` uses literal `@ID@` replacement instead of formatting the entire JSON5
stub. The supported `core/fmt/fmt.odin` scans `%`, `{` and `}` as format syntax
(lines around 706). Official current documentation confirms doubled braces are
literal escapes and single braces introduce Python-like formatting:
[Odin fmt documentation](https://pkg.odin-lang.org/core/fmt/).

A compiled probe executed:

```odin
text := `check: { kind: "pattern" }`
fmt.println(fmt.tprintf(text))
```

It exited 0 but printed:

```text
check: %!(MISSING ARGUMENT)%!(MISSING CLOSE BRACE)kind: "pattern" }
```

The original failure remains directly reproducible. Keep literal replacement and
its explanation. Escaping all stub braces is a credible alternative but adds
maintenance obligations whenever JSON5 examples change, with no user benefit.
Passing the stub as a `%s` argument would preserve it but does not perform the
required ID substitution; literal replacement already solves that problem.

## Implementation acceptance and limits

Require init ignore-file preservation, unchanged configuration creation, existing
selector/authoring tests, and normal full CI. Do not add repeated stochastic
compiler tests to CI; the retry boundary is better covered by deterministic fake
compiler failures where needed. No schema, selector, warning or suppression
contract should be removed by this cleanup. Baseline identity/adoption decisions
are investigated separately by the parallel agent.

Untested: other platforms, other compiler builds, representative long-running
compiler crash frequency, external consumers of documentation fields. These
limits support retaining public surfaces and workarounds, not claiming them
obsolete.

## Completed cleanup and verification

Removed the init cache-ignore append and the repository's unused ignore entry.
Existing user files are not migrated. Updated the generated rule scaffold's
evidence prompt to accept reproducible source or compiler evidence with matching
limits; no public field or selector changed. Retained both compiler retries and
the literal ID substitution workaround.

A separate pass applied the comment-cleanup skill to `topics.odin`,
`checks.odin` and `rule_cmd.odin`. Counts below use original physical comment
lines, including baseline-integration corrections; rewritten multiline comments may occupy fewer lines afterward. Comments
inside the generated scaffold string are product text and were changed before
the comment-only pass, so are excluded from these counts.

| File | Deleted | Rewritten | Kept | Rewritten lines afterward |
| --- | --- | --- | --- | --- |
| topics.odin | 2 | 5 | 41 | 4 |
| checks.odin | 2 | 5 | 16 | 3 |
| rule_cmd.odin | 1 | 3 | 4 | 1 |

The pass removed redundant narration, corrected unconditional-blocking and
resolved-name claims, clarified the opt-out audit condition, and replaced the
unsupported O(files) claim with the actual traversal benefit. A lexer comparison
verified unchanged code tokens, including all string literals, during that pass.
No unresolved TODO or unclear-code flag arose. Retained field/selector contracts,
JSON parsing constraints, syntax-versus-string distinction, and formatting
workaround context as deliberate judgment calls.

Baseline integration also corrected the semantic-subject and `baselineable`
comments to reflect snapshot identity; those comment-only corrections are included
in the table.

Validation: a private fresh binary at `/tmp/odx-m7-cleanup-bin` built with the
repository vet/style flags. The committed `7-cleanup-probe` compiled and passed
against it: existing `.gitignore` preserved byte-for-byte, configuration files
created, and no unused cache created. Full milestone CI is the parent task's
remaining validation responsibility.
