package app

f :: proc(s: []int) -> int #no_bounds_check {
	return s[0]
}
