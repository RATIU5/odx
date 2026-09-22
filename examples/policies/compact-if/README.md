# Compact conditionals

A project-owned warning rule requires `do` for a braced `if` body containing
exactly one return, call statement or assignment. Else chains, declarations,
multiple statements and defer are outside this rule. It counts syntax, not
runtime effects, and does not rewrite source.

From the repository root:

```sh
odin test examples/policies/compact-if
build/odx check --root examples/policies/compact-if --json
build/odx check --root examples/policies/compact-if --strict --json
build/odx policy --root examples/policies/compact-if --json
```

The native tests pass. The first check reports three intentional warnings and
exits 0; strict mode reports the same findings and exits 1. Set `severity` to
`error` in `.odx/topics/compact/R1.odx.md` to fail ordinary checks too.

Copy the directory, including `.odx`, and replace the deliberate violating
examples with your project source. The repository integration test checks
severity, strict mode, suppressions, baselines and source preservation.
