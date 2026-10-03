package wrap

import "core:slice"

smallest :: proc(s: []$T) -> T {
	return slice.min(s)
}

smallest_int :: proc(s: []int) -> int {
	return slice.min(s)
}
