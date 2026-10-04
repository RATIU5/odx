package app

f :: proc(ok: bool) {
	if ok do g(1)
	for i in 0 ..< 3 do g(i)
}

g :: proc(n: int) {
	_ = n
}
