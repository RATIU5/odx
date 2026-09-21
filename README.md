# odx

odx is a secondary vet pass: it turns on every guarantee the Odin compiler already offers
and enforces the conventions a project has explicitly agreed on, with a reason for every
rule and an escape hatch for every reason.

It does not make code good. It applies conventions a team already agreed on, consistently, to
agents and to CI.

## Never claim

- odx cannot verify an allocator matches its intended lifetime. It can verify the `#+vet` tag
  is present. The part that actually prevents bugs is outside a static checker's reach.
- Allocator flow is deliberately invisible to static analysis: the implicit context exists so
  callers can intercept it.
- odx cannot verify "documents who frees" is true, only that a doc comment exists.
- Rules that are taste rather than mechanics are indefensible. Naming, formatting and brace
  style are never built in.
- odx does not make code good.
- Putting odx in an agent's loop does not make the agent write better Odin. The M6 pilot
  below measured it and the independent columns got worse.

## What the M6 pilot showed

Ten tasks (base64, kv_parse, lru, matrix, path_join, ring, split_words, stack, tokenize,
version_parse) were each run through `claude -p` under three conditions: `bare` (no odx),
`for` (`odx for` output in the prompt) and `hook` (the edit and Stop hooks installed).
Compiled and tests-pass were scored by the harness; `violations` is `odx check` grading
its own conditions, and the Stop hook refused to end the session until that count was zero,
so `hook = 0` is the stopping condition, not a result.

| condition | compiled | tests pass | odx violations | turns | seconds |
|---|---|---|---|---|---|
| bare | 10/10 | 9/10 | 18 | 71 | 274 |
| for | 8/10 | 7/10 | 4 | 66 | 407 |
| hook | 8/10 | 7/10 | 0 | 104 | 349 |

The two independent columns regressed under both odx conditions, and `hook` cost 46% more
turns than `bare`. A second run of `ring` and `stack` (the two tasks that failed under odx)
passed under all three conditions, so those failures were noise; the regression on the
first run is still the only evidence there is. The agent-loop features (the eval harness,
`odx hook stop`) were removed on this evidence; re-litigating it needs a different
experiment, which does not belong in this binary. Raw rows, tab-separated
`task condition compiled tests_pass violations turns seconds`; the last six are the rerun:

```
base64	bare	true	true	4	7	37
base64	for	true	true	0	13	54
base64	hook	true	true	0	16	60
kv_parse	bare	true	true	0	8	26
kv_parse	for	true	true	0	10	170
kv_parse	hook	true	true	0	11	35
lru	bare	true	true	2	8	25
lru	for	true	true	0	6	23
lru	hook	true	true	0	8	30
matrix	bare	true	true	0	8	26
matrix	for	true	true	1	3	15
matrix	hook	true	true	0	11	33
path_join	bare	true	true	0	12	52
path_join	for	true	true	1	3	19
path_join	hook	true	true	0	7	35
ring	bare	true	true	4	4	16
ring	for	false	false	1	3	13
ring	hook	false	false	0	9	26
split_words	bare	true	true	1	4	16
split_words	for	true	true	0	7	29
split_words	hook	true	true	0	11	29
stack	bare	true	true	3	6	20
stack	for	false	false	0	8	27
stack	hook	false	false	0	11	41
tokenize	bare	true	false	0	8	26
tokenize	for	true	false	0	8	34
tokenize	hook	true	false	0	12	36
version_parse	bare	true	true	4	6	30
version_parse	for	true	true	1	5	23
version_parse	hook	true	true	0	8	24
ring	bare	true	true	0	10	26
ring	for	true	true	0	9	26
ring	hook	true	true	0	8	29
stack	bare	true	true	0	8	23
stack	for	true	true	0	11	42
stack	hook	true	true	0	7	26
```

## 1. Guarantees

The compiler cannot check that you passed it the right flags, and `#+vet explicit-allocators`
is a per-file tag with no global switch. `odx doctor` lists every guarantee the installed
compiler offers, whether `odin.flags` in `odx.json5` turns it on, which files opt out via
`#+vet !x` or `#+feature`, and how many pure/service files carry the allocator tag. It warns
when the compiler gained a flag the project has not adopted, so the set ratchets as Odin grows.
`odx check` enforces the per-file ones: a missing allocator tag is `allocators/R1`, a
`#+feature` opt-out without a `// reason: <why>` on its line is `odx/feature-optout`.

## 2. Dependencies

Roles are opt-in: `odx.json5` may assign roles (pure, service, edge) per package directory
and say who may import whom; `odx check` then reports forbidden imports, mutable globals outside
edge, foreign blocks outside edge, and an exported procedure that passes another package's error
type through its boundary, each with a reason and an escape hatch. A package with no role gets
no rule. The forbidden-import check reads direct import lines; for the transitive picture the
compiler's own `odin check -show-import-graph` is the source, not odx.

## 3. The rulebook

Three built-in topics (`errors`, `allocators`, `dependencies`), four active rules
(`allocators/R1`, `dependencies/R2`, `dependencies/R3`, `errors/R3`), one file per rule:
`rules/<topic>/<id>.odx.md` is Markdown whose frontmatter is the members of one JSON5 object
(`key: "value",` per line, no dialect) and three fenced blocks. ` ```odin prelude ` is a
sibling file of shared types; ` ```odin fires ` must produce that rule and no other finding;
` ```odin silent ` must compile and produce nothing. `odx self-test` compiles every block, so
the documentation, the exemplar and the test are one artifact that cannot drift. The prose
around them is the `odx explain` body and what the hook shows the model, violating form beside
the correct one. Every rule carries `why`, `instead_of`, `evidence`, `cost` and a severity; a
rule missing any fails to load. Every rule is mechanical and every finding counts; there is no
advisory tier. Conventions only a reader can enforce live in `rules/<topic>/topic.md` under a
`## Reader checks` heading, statement and why plus a fires/silent pair; `odx self-test`
compiles those blocks too, `odx explain --checklist` prints them, and `odx for` and the
generated `CLAUDE.md` section carry their statements. `topic.md` also carries the topic record
in its frontmatter. `odx for <path>` prints the rules that apply to a file, so one call is
enough to write it; `--brief` gives topic names only. A project adds `.odx/topics/<name>/` in
the same format; the same name overrides the built-in.

Adding an idiom is a text edit, not a recompile. `check: { kind: pattern, match: <class>, ... }`
selects an AST node class (`call`, `import`, `proc`, `decl`) and filters it: `name`/`names`
for calls and import globs, `exported` and `requires_param: { index, type_suffix }` for
procedures, `at: package_scope, mutable: true` for declarations, plus `roles`/`except_roles`.
No regex over source text. `odx rule try '<check json5>' [paths]` prints every match of a
candidate spec with its count before any file exists (`--file <rule.odx.md>` dry-runs a
draft); `odx rule add <topic>` scaffolds the next free id; `odx rule test <topic>/<id>`
compiles just that rule's blocks.

```
odx check [<path>...]            run the checks (exit 1 on violations; odx.baseline softens, never hides)
odx for <path>                   topics that apply to a file or package (by role)
odx for --emit-claude-md [<path>]   the same as a Markdown section for CLAUDE.md (no path: every topic)
odx explain [<topic>] [--rule R3]   no topic: list topics; with one: rules, rationale, do/don't
odx explain --checklist          the reader checks from every topic.md, for an adversarial reviewer
odx ignores [--stale]            every odx:ignore suppression; --stale: suppressing nothing
odx baseline add | regen         freeze current violations by semantic key (shrinks on its own)
odx doctor [--ci]                guarantees, toolchain, config errors, task-file drift
odx hook edit                    Claude Code PostToolBatch hook: report after an edit, exit 0
odx init [--hooks]               write odx.json5 and mise.toml (--hooks: the edit hook and a CLAUDE.md section)
odx self-test                    odx's own fixture runner
odx rule try | add | test        measure a candidate check, scaffold a rule file, run one rule's blocks
```

Global flags: `--json`, `--root <dir>`. Exit codes are contract: `0` clean, `1` violations,
`2` tool or config error (`hook edit` always exits 0).

## Agent interface

odx is invoked by agents and CI; it never referees a session. The interface is three things:

- `odx check --json` (schema below): every finding carries `fix_hint` (what to write
  instead) and `ignore_syntax` (the exact suppression comment), so a consumer acts on one
  call. `odx doctor --json` returns `{schema, errors, warnings}`; `odx for --json` the
  topics for a path.
- `odx for --emit-claude-md` prints the applicable rules as a Markdown section. `odx init
  --hooks` writes it into `CLAUDE.md` once, at setup, where it costs nothing per turn;
  regenerate it after editing `rules/`.
- `odx hook edit`, the one hook `odx init --hooks` installs (PostToolBatch). It leads with
  the compiler: parse errors, then `odin check` on the touched package, and only when that
  is clean odx's own rules. With no file path it scopes to the files changed since `HEAD`
  plus untracked ones. Findings go to stdout, capped at 50 with an explicit omitted count,
  and the exit code is always 0. Nothing odx installs can block an edit or hold a session
  open; the M6 pilot above is why.

## Adopting on an existing codebase

`odx baseline regen` writes `odx.baseline`: one `<rule>\t<package>\t<subject>` line per current
violation, keyed on the rule's semantic subject (an import path, a symbol, a declaration
name), never on line numbers or text. A baselined violation still prints, marked
`[baselined]`, and appears in `--json`; it just stops failing the build. A full `odx check`
drops entries that no longer fire; `--ci` never rewrites and fails if a shrink would have
occurred. Growth needs an explicit `odx baseline add`. `odx check --since <ref>` checks only
the packages with changes since a git ref.

## Escape hatches

`// odx:ignore <topic>/<R> reason: <at least ten characters>` on the line above, or at the
end of the line, suppresses one finding; `odx:ignore-file` on lines 1-3 suppresses it for the
file. A near miss (`odx: ignore`, a missing rule id, a short reason) is `odx/bad-ignore`, never
silently ignored. An ignore that suppresses nothing is `odx/stale-ignore`; nothing deletes it
for you. Suppressions added on a branch are a git question:
`git diff -U0 HEAD | grep '^+.*odx:ignore'`. Every rule is ignorable. Nothing in odx refuses
an edit.

The rulebook (`rules/`, `odx.json5`, `tests/fixtures/`) is reviewed the way any other source
is: `git status --porcelain -- rules/ odx.json5 tests/fixtures/` says what changed, and the
generated `CLAUDE.md` section tells an agent to ask before editing them. There is no lock.

## Formats and output

Two formats, total. `odx.json5` is project configuration only: `version: 1`, `roles`,
`default_role`, `exclude`, `disabled`, `dependencies`, `odin` (flags, collections, allowed
vet disables, explicit-allocators policy); one schema, and an unknown key is a load error.
`.odx.md` is everything a human writes about rules: `topic.md` for the topic record and
`<id>.odx.md` per rule, frontmatter plus fenced blocks. `odx.baseline` is written by odx,
never by hand.

`--json` on `check` and `ignores` is the machine contract, `schema: 1`; fields are only
added under that number and `schema` bumps on any break. Each violation carries `file`,
`line`, `col`, `rule`, `severity`, `check`, `message`, `class` (the rule's stable greppable
name), `subject` (the baseline key), `baselined`, `blocking` (always true; kept for schema 1), `ignorable`, `statement`,
`why`, `fires`, `silent`, `fix_hint` (the rule's `instead_of`) and `ignore_syntax` (the
suppression comment, `""` when the rule takes none). `summary` carries `errors`,
`warnings` (baselined findings count in neither), `ignored`, `files`, `baselined` and
`omitted`: `--max-violations` is unlimited by default and 50 on the hook path, and a
truncated report always says how many it dropped.

## Layout

- `odx/` the tool. `rules/<topic>/` built-in topics (`topic.md` record + prose, one
  `<id>.odx.md` per rule, `example/<pkg>/` a compiling exemplar), embedded into the binary.
- `.odx/topics/<name>/` project topics in the same format.
- `tests/fixtures/<name>/` small projects with `// want: topic/R2` markers, diffed both ways
  by `odx self-test`. `tests/compiler/` holds constructs the compiler now rejects on its own;
  `mise run audit` fails if one ever compiles again, which means odx needs a rule back.

## Develop

```
mise run build      # build/odx
mise run test       # unit tests (address sanitizer on)
mise run fixtures   # odx self-test
mise run exemplars  # every rules/*/example/* compiles and passes its topic
mise run audit      # compiler-owned constructs are still compiler errors
mise run ci         # all of the above + odx doctor --ci + odx checking itself
```
