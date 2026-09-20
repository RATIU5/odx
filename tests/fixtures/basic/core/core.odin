// odx:ignore-file allocators/R1 reason: fixture keeps the tag off to test file ignores
package core

import "core:os" // want: layering/R2
import "core:strings"

count: int // mutable global in pure // want: layering/R3

Error :: enum {
	None,
	Bad,
}

// no attribute: errors/R3
parse :: proc(s: string) -> (n: int, err: Error) { // want: errors/R3
	return len(s), .None
}

@(require_results)
ok :: proc() -> Error {
	return .None
}

Point :: struct {
	x, y: int,
}

// odx:ignore layering/R3 reason: this global is a fixture for an own-line ignore
origin: Point

stale: int // odx:ignore layering/R2 reason: wrong rule id so this ignore is stale // want: layering/R3 odx/stale-ignore

use :: proc(p: Point) -> int {
	count += 1 // odx:ignore layering/R9 reason: unknown rule, reported as bad-ignore // want: odx/bad-ignore
	return p.x + p.y + len(os.args) + len(strings.to_upper("x", context.temp_allocator))
}
