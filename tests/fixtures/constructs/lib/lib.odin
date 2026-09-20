#+feature using-stmt
package lib

import sys "core:os" // want: layering/R2

Point :: struct {
	x, y: int,
}

foreign import libc "system:c" // want: layering/R4

sum :: proc(p: Point) -> int {
	using p // want: local/R1
	return x + y
}

first :: proc(xs: []int) -> int {
	#no_bounds_check { // want: local/R2
		return xs[0]
	}
}

quit :: proc() {
	sys.exit(1) // want: local/R3
}

die :: proc() {
	panic("no") // want: local/R3
}

_ :: libc
