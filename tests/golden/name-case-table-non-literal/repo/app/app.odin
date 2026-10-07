package app

Pair :: struct {
	a, b: int,
}

count: int

total := 5

started := start()

pair: Pair

COUNT: int

TOTAL := 5

STARTED := start()

PAIR: Pair

start :: proc "contextless" () -> int {
	return 1
}

sum :: proc() -> int {
	local := Pair{1, 2}
	LOCAL := Pair{3, 4}
	return local.a + LOCAL.b
}
