---
name: "errors",
summary: "Typed errors, @(require_results), or_return; never discard a failure",
tags: ["errors", "results", "or_return", "require_results"],
aliases: ["error handling", "failure", "fallible", "boolean result", "ok flag"],
applies_to: { roles: ["pure", "service", "edge"] },
related: ["dependencies"],
example_roles: { "example/core": "pure" },
---

Failures are values. Every fallible procedure says so in its signature and the compiler refuses
to let a caller drop that value. Handle it where it occurs when you can; when a package's
operations genuinely chain, `or_return` carries it up to the one place that can act on it.

- `_ = f()` is only acceptable at the top of a program where the error is logged and the
  process exits. Write the log line.
- `Error` may be a `union` when a package wraps errors from several dependencies.

## Reader checks

Conventions a reader enforces in review; `odx explain --checklist` lists them and
`odx self-test` compiles every block below, so the examples cannot rot. Nothing here fires.

### Exported procedures that can fail return an error type as the last result, not a bool.

A bool, and equally a single universal error type, is 'all the same degenerate value: error or not... a fancy boolean'. Callers cannot branch on it or report it.

A bool says that something failed, never what.

```odin fires
open :: proc(path: string) -> (handle: int, ok: bool) {
	return 0, len(path) > 0
}
```

```odin silent
Error :: enum {
	None,
	Not_Found,
	Permission,
}

@(require_results)
open :: proc(path: string) -> (handle: int, err: Error) {
	return 0, .Not_Found if len(path) == 0 else .None
}
```

### Each package declares one Error enum or union; no string or any errors.

'Having an error value type defined per package is absolutely fine (and ergonomic too)'. A typed error is exhaustively switchable and greppable; strings and any are neither.

One switchable type per package; a `union` when it wraps several dependencies.

```odin fires
load :: proc(path: string) -> (size: int, problem: string) {
	if len(path) == 0 {return 0, "empty path"}
	return len(path), ""
}
```

```odin silent
Error :: enum {
	None,
	Empty_Path,
}

@(require_results)
load :: proc(path: string) -> (size: int, err: Error) {
	if len(path) == 0 {return 0, .Empty_Path}
	return len(path), .None
}
```

### Handle an error where it occurs when you can; when a package's operations genuinely chain, prefer or_return over hand-written `if err != nil { return }`.

'You make your mess; you clean it.' Local handling is the default; or_return is a per-package tool ('when a package needs it, it REALLY needs it') that keeps a chained happy path linear.

The hand-written form says the same thing in four lines that `or_return` says in one token.

```odin fires
Error :: enum {
	None,
	Bad,
}

@(require_results)
step :: proc(x: int) -> Error {
	return .Bad if x < 0 else .None
}

@(require_results)
run :: proc(x: int) -> Error {
	err := step(x)
	if err != .None {
		return err
	}
	return step(x + 1)
}
```

```odin silent
Error :: enum {
	None,
	Bad,
}

@(require_results)
step :: proc(x: int) -> Error {
	return .Bad if x < 0 else .None
}

@(require_results)
run :: proc(x: int) -> Error {
	step(x) or_return
	return step(x + 1)
}
```
