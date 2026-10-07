package app

run :: proc() -> int {
	Handle :: distinct int
	next :: proc() -> int {
		id :: Handle
		return int(id(1))
	}
	return next()
}
