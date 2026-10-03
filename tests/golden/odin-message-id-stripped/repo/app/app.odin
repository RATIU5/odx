package app

import "core:slice"

sort_names :: proc() {
	names := []string{"a"}
	slice.sort_by(names, proc(a: string, b: int) -> bool { return false })
}
