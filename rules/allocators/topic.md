# allocators

Memory ownership is part of a procedure's contract. In pure and service code the allocator is
a parameter, so each allocation's lifetime is chosen at the call site by a specific allocator
rather than inherited implicitly, and the compiler (`#+vet explicit-allocators`) refuses an
allocation that forgot to say. odx checks that the tag is present; whether an allocator matches
its intended lifetime is outside any static checker's reach.

## Do

```odin
#+vet explicit-allocators
package core

// Caller owns the result; free with delete(result, allocator).
split_words :: proc(s: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	...
	return out[:]
}
```

## Don't

```odin
package core                          // R1: missing #+vet explicit-allocators
words := make([dynamic]string)        // hidden context.allocator; who frees it?
```

## Notes

- Edge packages (main, platform) may use `context.allocator` freely; they own the process.
- `context.temp_allocator` is fine for values that die before the next frame or request; say so in a comment.
- A file whose job is to set `context.allocator` (an arena for a subsystem) is the interception
  point the context system exists for; it is not what R1 is about.
- R1 and R2 do not conflict: the tag rejects *relying* on the default at a call site, not
  declaring `allocator := context.allocator` as a parameter. Inside a tagged file the default
  is unreachable from other tagged files, so it serves untagged callers.
