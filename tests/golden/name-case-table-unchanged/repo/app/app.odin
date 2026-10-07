package app

Pair :: struct {
	a, b: int,
}

NAMES := [?]string{"a", "b"}

ORDER := []int{3, 1, 2}

ORIGIN := Pair{0, 0}

first :: proc() -> string {
	return NAMES[0]
}

count :: proc() -> (n: int) {
	for name in NAMES {
		n += len(name)
	}
	return n + len(NAMES)
}
