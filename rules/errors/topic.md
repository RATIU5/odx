---
name: "errors",
summary: "Project-selected result acknowledgement and contextual error review",
tags: ["errors", "results", "or_return", "require_results"],
aliases: ["error handling", "failure", "fallible", "boolean result", "ok flag"],
applies_to: { roles: ["pure", "service", "edge"] },
related: ["dependencies"],
example_roles: { "example/core": "pure" },
---

Choose error representations for the decisions callers need to make. The active declaration
rule requires `@(require_results)` on selected exported APIs, using configurable canonical
name suffixes and optional structural heuristics. It does not prove error intent or correct
handling. The compiler permits explicit discard, including just the error result.

## Reader checks

These questions guide review; `odx check` does not enforce them. Executable examples show
valid Odin, not proof of caller behavior. Neither example form below is a policy finding.

### Does the result communicate the information callers need?

Predicates and lookup success flags legitimately return bool. Use richer error values when
callers need failure details; a bool result alone does not establish an error-design defect.

```odin silent
contains :: proc(values: map[int]int, key: int) -> bool {
	_, ok := values[key]
	return ok
}

lookup :: proc(values: map[int]int, key: int) -> (int, bool) {
	value, ok := values[key]
	return value, ok
}
```

### Do error domains fit their operations and callers?

Several error types in one package, a shared domain, and dependency error reuse can each be
appropriate. Consider whether callers can inspect and report useful details. No exactly-one
error-type or blanket string/any prohibition is enforced here.

```odin silent
Read_Error :: enum {None, Missing}
Write_Error :: enum {None, Full}

@(require_results)
read :: proc() -> Read_Error {return .Missing}

@(require_results)
write :: proc() -> Write_Error {return .Full}
```

### Is handling or propagation clear, and is explicit discard intentional?

Review recovery and ownership where the operation occurs. Explicit branches and `or_return`
are both valid propagation styles. `@(require_results)` establishes acknowledgement only;
it permits storing an unchecked result or explicitly discarding one. Review the consequences
of discard in context; no universal logging or process-exit requirement follows from Odin.

```odin silent
Error :: enum {None, Bad}

@(require_results)
step :: proc(x: int) -> Error {return .Bad if x < 0 else .None}

@(require_results)
explicit :: proc(x: int) -> Error {
	err := step(x)
	if err != .None {return err}
	return step(x + 1)
}

@(require_results)
propagate :: proc(x: int) -> Error {
	step(x) or_return
	return step(x + 1)
}

acknowledge :: proc() {
	_ = step(-1)
}
```
