# odx

A queryable rulebook and checker for Odin projects. One CLI that tells an LLM (or a human)
which conventions apply to the code it is about to write, and checks the code against them.

```
odx topics                       list topics
odx explain <topic> [--rule R3]  rules, rationale, do/don't
odx for <path>                   topics that apply to a file or package (by role)
odx check [<path>...]            run the checks (exit 1 on violations)
odx doctor [--ci]                toolchain, flags, mise.toml drift, overrides
odx ext list | ext validate      project extensions in .odx/ and odx.json5
odx init                         write odx.json5 and mise.toml for a project
```

Global flags: `--json`, `--root <dir>`. Exit codes: 0 clean, 1 violations, 2 tool/config error.

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
finding is marked on line 1 of any file in that package.
