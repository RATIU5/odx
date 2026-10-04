package app

f :: proc(s: []int) -> int {
	total := 0
	#no_bounds_check for i in 0 ..< len(s) {
		total += s[i]
	}
	#bounds_check {
		total += s[0]
	}
	#no_bounds_check first := s[0]
	return total + first
}
