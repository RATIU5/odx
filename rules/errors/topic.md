---
name: "errors",
summary: "Typed errors, @(require_results), or_return; never discard a failure",
tags: ["errors", "results", "or_return", "require_results"],
aliases: ["error handling", "failure", "fallible", "boolean result", "ok flag"],
example_questions: ["how do I return failures from a proc", "should this return a bool or an error", "how do I propagate an error to the caller"],
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
