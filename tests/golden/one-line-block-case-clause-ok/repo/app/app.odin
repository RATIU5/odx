package app

f :: proc(n: int) {
	switch n {
	case 1: g(1)
	case: g(0)
	}
}

g :: proc(n: int) {
	_ = n
}
