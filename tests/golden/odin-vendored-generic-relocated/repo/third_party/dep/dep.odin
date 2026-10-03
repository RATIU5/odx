package dep

import "base:intrinsics"

smaller :: proc(a, b: $T) -> T where intrinsics.type_is_ordered(T) {
	return a if a < b else b
}
