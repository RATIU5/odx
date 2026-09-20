# odx

A queryable rulebook and checker for Odin projects. One CLI that tells an LLM (or a human)
which conventions apply to the code it is about to write, and checks the code against them.

```
odx topics                       list topics
odx explain <topic> [--rule R3]  rules, rationale, do/don't
odx for <path>                   topics that apply to a file or package (by role)
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
mise run exemplars  # every rules/*/example/* compiles
mise run ci         # all of the above + odx validating itself
```
