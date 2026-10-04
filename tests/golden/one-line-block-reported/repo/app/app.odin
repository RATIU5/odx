package app

f :: proc(ok: bool) -> int {
	if ok {return 1}
	for i in 0 ..< 3 {g(i)}
	{g(4)}
	when ODIN_DEBUG {g(5)}
	if !ok {g(6)} else {g(7)}
	return 0
}

g :: proc(n: int) {
	_ = n
}
