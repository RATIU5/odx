package app

// #no_bounds_check in a comment is not a directive.
f :: proc(s: []int) -> int {
	total := 0
	for i in 0 ..< len(s) {
		total += s[i]
	}
	return total
}
