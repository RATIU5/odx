package app

_ := next()

next :: proc "contextless" () -> int {
	return 1
}

pair :: proc() -> (int, bool) {
	return 1, true
}

count :: proc(items: []int, _: bool) -> (n: int) {
	_, ok := pair()
	for _ in items {
		n += 1
	}
	for _, _ in items {
		n += 1
	}
	if !ok {
		n = 0
	}
	return
}
