---
name: "allocators",
summary: "Required allocator vet directives and review of allocation ownership",
tags: ["allocators", "memory", "arena", "defer", "leaks"],
aliases: ["memory management", "allocation", "context.allocator"],
applies_to: { roles: ["pure", "service"] },
related: ["errors", "dependencies"],
example_roles: { "example/core": "pure" },
---

Memory ownership is part of a procedure's contract. This project's default policy
requires `#+vet explicit-allocators` in pure and service files. odx checks for the
directive before the package declaration. The compiler rejects affected calls
that omit allocator parameters; this does not detect all allocation, require an
allocator parameter on every allocating procedure, or prove ownership and lifetime.

- Explicit `context.allocator` and `context.temp_allocator` arguments are allowed.
- `append` uses the container's allocator; even appending to a zero-initialized
  dynamic array can inherit context without an explicit allocator argument.
  APIs such as `fmt.tprintf` can allocate scratch memory internally.
- Replacing context to intercept a subsystem is a legitimate Odin design. It
  does not exempt a file from R1 or an affected call from compiler vetting.
  Choose role/configuration scope or a reasoned file ignore for deliberate exceptions.
- Declaring `allocator := context.allocator` remains valid. Tagged callers must
  supply that argument; untagged callers can use the default.
- Run Odin tests with the sanitizer settings appropriate for the project.
  Sanitized test execution does not prove memory safety for all inputs.

## Reader checks

Conventions a reader enforces in review; `odx policy --checklist` lists them and
Native repository tests compile the blocks below to check language validity. Compilation
does not establish that a reader followed the convention. Nothing here fires.

### Review allocation ownership and choose explicit parameters or documented context/container allocation deliberately.

For caller-owned results, an allocator parameter can let callers choose an arena
or tracker. Document who frees the result and which allocator to use. A parameter
does not prove that the implementation uses it. Owned containers, internal scratch
work, and deliberate context interception are legitimate alternatives when their
contracts fit the API. Parameter position is a project style choice.

Scratch values must not outlive the reset or other invalidation of their actual
allocator; that boundary may occur before the next frame or request. Document
the boundary and review any escaping references. The first example below leaves
ownership implicit; the second documents a caller-owned result and allocator.

```odin fires
words :: proc(s: string) -> []string {
	out := make([dynamic]string)
	append(&out, s)
	return out[:]
}
```

```odin silent
// Caller owns the result; free with delete(result, allocator).
words :: proc(s: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	append(&out, s)
	return out[:]
}
```
