package app

// do in a comment is not a statement.
f :: proc(ok: bool) {
	if ok {
		g(1)
	}
}

g :: proc(n: int) {
	_ = n
}
