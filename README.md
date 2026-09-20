# odx

A queryable rulebook and checker for Odin projects. One CLI that tells an LLM (or a human)
which conventions apply to the code it is about to write, and checks the code against them.
Per-file rule scoping already exists in every agent host; what odx adds is rules that are
simultaneously the check: one rule id the model can look up and CI can fail on.

```
odx topics                       list topics
odx explain <topic> [--rule R3]  rules, rationale, do/don't
odx for <path>                   topics that apply to a file or package (by role)
odx check [<path>...]            run the checks (exit 1 on violations)
odx doctor [--ci]                toolchain, flags, mise.toml drift, overrides, protected-path lock
odx fix [--propose]              delete stale odx:ignore directives (refuses on a dirty worktree)
odx explain --checklist          manual rules only, for an adversarial reviewer
odx hook edit | stop | changed   Claude Code hook entry points
odx api [<path>...]              public API snapshot per package in api/<pkg>.txt; exit 1 on drift
odx new <template> <Name>        scaffold a package from a template (odx new --list)
odx ext list | ext validate      project extensions in .odx/ and odx.json5
odx init                         write odx.json5 and mise.toml for a project
```

Global flags: `--json`, `--root <dir>`. Exit codes: 0 clean, 1 violations, 2 tool/config error.

## LLM loop

`odx init --hooks` writes `.claude/settings.json` (PostToolBatch runs `odx hook edit`, syntax
and rule checks only; FileChanged on a protected path runs `odx hook changed`, the lock
verification; Stop runs `odx hook stop`, the full check) and a short `CLAUDE.md` section. The
Stop hook exits 0 when `stop_hook_active` is set and gives up loudly after `ODX_STOP_GUARD_MAX`
(default 3, stricter than the harness cap of 8) identical blocks. Hook output is capped at 50
violations with an explicit omitted count.

Protected paths (`rules/`, `.odx/`, `odx.json5`, `mise.toml`, `tests/fixtures/`,
`.claude/settings.json`, `CLAUDE.md`) are hash-locked in `.odx/lock`. `odx doctor --verify-rulebook`
(implied by `--ci`) and the Stop hook name every changed file; a human approves with
`ODX_ALLOW_PROTECTED=1 odx doctor --relock`. This is visibility, not a security boundary.

## Layout

- `odx/` the tool. `rules/<topic>/` built-in topics (`topic.json5` metadata + rules,
  `topic.md` prose, `example/<pkg>/` a compiling exemplar), embedded into the binary.
- A project adds `.odx/topics/<name>/` in the same format; same name overrides the built-in.
- `odx.json5` maps package directories to roles (pure, service, edge) and lists disabled rules.

## Develop

```
mise run build      # build/odx
mise run test       # unit tests (address sanitizer on)
mise run fixtures   # odx self-test: tests/fixtures/*/ diffed against their // want: markers
mise run exemplars  # every rules/*/example/* compiles and passes its topic
mise run ci         # all of the above + odx doctor --ci + odx checking itself
```

A fixture is a small project under `tests/fixtures/<name>/` with its own `odx.json5`; each
offending line carries `// want: topic/R2` (several ids space-separated). A package-level
finding is marked on line 1 of any file in that package. A fixture with an `api/` directory
also verifies its snapshots; every template is rendered as `Sample` and checked.

## API snapshots

`odx api` writes one sorted text file per package under `api/`: one fully qualified line per
exported entity with resolved types and the whitelisted attributes (`require_results`,
`deprecated`, `odx_*`). A later run diffs structurally (added, removed, changed by entity) and
exits 1; `ODX_UPDATE_SNAPSHOTS=1 odx api` re-blesses and the git diff is the review. Reading a
`.odin-doc` from an unsupported doc-format version is a tool error naming both versions.

## Templates

`odx new <template> <Name>` renders `templates/<name>/` (built in) or `.odx/templates/<name>/`
into the role's directory from `odx.json5` (or `--dir`). Placeholders: `{{Name}}`,
`{{name_snake}}`, `{{name_upper}}`. It never overwrites.
