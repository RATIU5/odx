// odx:ignore-file allocators/R1 reason: fixture keeps the tag off to test file ignores
package core

import "core:os" // want: dependencies/R2
import "core:strings"

count: int // mutable global in pure // want: dependencies/R3

Error :: enum {
	None,
	Bad,
}

// no attribute: errors/R3
parse :: proc(s: string) -> (n: int, err: Error) { // want: errors/R3
	return len(s), .None
}

// passes os's error type through the package boundary: errors/R5 (and no attribute: R3)
read :: proc(path: string) -> ([]byte, os.Error) { // want: errors/R3 errors/R5
	return os.read_entire_file(path, context.allocator)
}

@(require_results)
ok :: proc() -> Error {
	return .None
}

Point :: struct {
	x, y: int,
}

// odx:ignore dependencies/R3 reason: this global is a fixture for an own-line ignore
origin: Point

stale: int // odx:ignore dependencies/R2 reason: wrong rule id so this ignore is stale // want: dependencies/R3 odx/stale-ignore

use :: proc(p: Point) -> int {
	count += 1 // odx:ignore dependencies/R9 reason: unknown rule, reported as bad-ignore // want: odx/bad-ignore
	return p.x + p.y + len(os.args) + len(strings.to_upper("x", context.temp_allocator))
}
