# allocators

Memory ownership is part of a procedure's contract. In pure and service code the allocator is
a parameter, so the caller decides between the heap, an arena, or a tracking allocator in
tests, and the compiler (`#+vet explicit-allocators`) refuses an allocation that forgot to say.

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
