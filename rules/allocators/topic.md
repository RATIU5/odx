---
name: "allocators",
summary: "Explicit allocator parameters in pure code; each allocation's lifetime is chosen at the call site",
tags: ["allocators", "memory", "arena", "defer", "leaks"],
aliases: ["memory management", "allocation", "context.allocator"],
example_questions: ["who frees this slice", "should this proc take an allocator parameter", "how do I avoid leaks in tests"],
applies_to: { roles: ["pure", "service"] },
related: ["errors", "dependencies"],
example_roles: { "example/core": "pure" },
---

Memory ownership is part of a procedure's contract. In pure and service code the allocator is
a parameter, so each allocation's lifetime is chosen at the call site by a specific allocator
rather than inherited implicitly, and the compiler (`#+vet explicit-allocators`) refuses an
allocation that forgot to say. odx checks that the tag is present; whether an allocator matches
its intended lifetime is outside any static checker's reach.

- Edge packages (main, platform) may use `context.allocator` freely; they own the process.
- `context.temp_allocator` is fine for values that die before the next frame or request; say so in a comment.
- A file whose job is to set `context.allocator` (an arena for a subsystem) is the interception
  point the context system exists for; it is not what R1 is about.
- R1 and R2 do not conflict: the tag rejects *relying* on the default at a call site, not
  declaring `allocator := context.allocator` as a parameter. Inside a tagged file the default
  is unreachable from other tagged files, so it serves untagged callers.
- Sanitized tests (`-sanitize:address -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`) are a
  guarantee `odx doctor` checks in mise.toml, not a rule (the former R3, retired in M8.3).
