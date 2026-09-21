# odx

odx is a secondary vet pass: it turns on every guarantee the Odin compiler already offers,
enforces the conventions a project has explicitly agreed on, and reports what each package
actually depends on, with a reason for every rule and an escape hatch for every reason.

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
- The retrieval half of the premise (rules in an agent's context) is unmeasured by anyone
  until the M6 evaluation runs.

## 1. Guarantees

The compiler cannot check that you passed it the right flags, and `#+vet explicit-allocators`
is a per-file tag with no global switch. `odx doctor` lists every guarantee the installed
compiler offers, whether `odin.flags` in `odx.json5` turns it on, which files opt out via
`#+vet !x` or `#+feature`, and how many pure/service files carry the allocator tag. It warns
when the compiler gained a flag the project has not adopted, so the set ratchets as Odin grows.
`odx check` enforces the per-file ones: a missing allocator tag is `allocators/R1`, a
`#+feature` opt-out without a `// reason: <why>` on its line is `odx/feature-optout`.

## 2. Dependencies

With no configuration at all, `odx doctor` and `odx for <path>` report what every package
transitively reaches: the OS, the network, threads, or a `foreign` block, and through which
import. The graph is the compiler's own (`-show-import-graph`), not a taxonomy. Turning a reach
into a rule is opt-in: `odx.json5` may assign roles (pure, service, edge) per package directory
and say who may import whom; `odx check` then reports forbidden imports, mutable globals outside
edge, foreign blocks outside edge, and an exported procedure that passes another package's error
type through its boundary, each with a reason and an escape hatch. A package with no role gets
the report and no rule.

## 3. The rulebook

Three built-in topics (`errors`, `allocators`, `dependencies`), ten active rules, one file per
rule: `rules/<topic>/<id>.odx.md` is Markdown with restricted frontmatter (`key: value`, inline
JSON5 for `check:`) and three fenced blocks. ` ```odin prelude ` is a sibling file of shared
types; ` ```odin fires ` must produce that rule and no other finding; ` ```odin silent ` must
compile and produce nothing. `odx self-test` compiles every block, so the documentation, the
exemplar and the test are one artifact that cannot drift. The prose around them is the
`odx explain` body and what the hook shows a blocked model, violating form beside the correct
one. Every rule carries `why`, `instead_of`, `evidence`, `cost`, a severity and `blocking`; a
rule missing any fails to load. `kind: example` rules have no check: they are compiled
fires/silent pairs surfaced by `odx for`, `odx explain --checklist` and the block text, never
blocking. There is no prose-only rule kind. `rules/<topic>/topic.md` carries the topic record
in its frontmatter. `odx for <path>` prints the rules that apply to a file,
most important first, so one call is enough to write it; `--brief` gives topic names only. A
project adds `.odx/topics/<name>/` in the same format; the same name overrides the built-in.

```
odx check [<path>...]            run the checks (exit 1 on violations; odx.baseline softens, never hides)
odx for <path>                   topics that apply to a file or package (by role)
odx explain [<topic>] [--rule R3]   no topic: list topics; with one: rules, rationale, do/don't
odx explain --checklist          manual rules only, for an adversarial reviewer
odx ignores [--added] [--stale]  every odx:ignore suppression; --added: not in HEAD; --stale: suppressing nothing
odx baseline add | regen         freeze current violations by semantic key (shrinks on its own)
odx doctor [--ci]                guarantees, toolchain, config errors, task-file drift, protected-path lock
odx hook edit | stop | changed   Claude Code hook entry points
odx init [--hooks]               write odx.json5 and mise.toml for a project
odx self-test                    odx's own fixture runner
```

Global flags: `--json`, `--root <dir>`. Exit codes: 0 clean, 1 violations, 2 tool/config error.

## Agent loop

`odx init --hooks` writes `.claude/settings.json` (PostToolBatch runs `odx hook edit`;
FileChanged on a protected path runs `odx hook changed`; Stop runs `odx hook stop`, the full
check) and a short `CLAUDE.md` section.

The edit hook leads with the compiler: parse errors, then `odin check` on the touched
package, and only when that is clean odx's own rules. With no file path it scopes to the files
changed since `HEAD` plus untracked ones, and checks nothing when nothing changed. A block
message is self-sufficient: the first violation of each rule carries the statement, the why,
and the exact `odx:ignore` syntax when the rule takes one. The Stop hook escalates instead of
repeating: the second identical block appends the compiling exemplar of every topic involved,
and the `ODX_STOP_GUARD_MAX`-th (default 3, deliberately stricter than the harness cap of 8)
states that the remaining violations are not fixed and exits 0. Output is capped at 50
violations with an explicit omitted count. The Stop hook also prints how many baselined
violations remain and how many suppressions were added since `HEAD`.

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
for you. `odx ignores --added` lists the suppressions not present in `HEAD`. Every rule is
ignorable. Nothing in odx refuses an edit.

Protected paths (`rules/`, `.odx/`, `odx.json5`, `mise.toml`, `tests/fixtures/`,
`.claude/settings.json`, `CLAUDE.md`) are hash-locked in `.odx/lock`. `odx doctor
--verify-rulebook` (implied by `--ci`) names every changed file and CI fails on drift; the
hooks print it and let the edit stand. A human approves with `ODX_ALLOW_PROTECTED=1 odx
doctor --relock`. This is visibility, not a security boundary.

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
