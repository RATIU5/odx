package app

later :: struct {}

run :: proc() -> int {
	later := 1
	next :: proc() -> int {
		after :: later
		After :: later
		first: after
		second: After
		return size_of(first) + size_of(second)
	}
	return later + next()
}
