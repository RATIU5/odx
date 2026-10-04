package app

f :: proc(ok: bool) -> int {
	if ok {
		return 1
	}
	for i in 0 ..< 3 {
		g(i)
	}
	return 0
}

g :: proc(n: int) {
	_ = n
}
