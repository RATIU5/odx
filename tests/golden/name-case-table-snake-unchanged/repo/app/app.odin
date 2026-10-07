package app

lookup := [?]int{1, 2}

Pair :: struct {
	a, b: int,
}

origin := Pair{0, 0}

first :: proc() -> int {
	return lookup[0] + origin.a
}

bump :: proc() {
	lookup[0] += 1
	origin.a = 2
}
