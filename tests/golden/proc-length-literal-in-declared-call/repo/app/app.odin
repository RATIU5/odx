package app

apply :: proc(a: int, f: proc(a: int) -> int) -> int {
	return f(a)
}

g :: proc() -> int {
	total := apply(1, proc(a: int) -> int {
		weight := 0
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		weight += 1
		return a + weight
	})
	return total
}
