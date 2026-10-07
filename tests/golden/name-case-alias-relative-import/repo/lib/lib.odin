package lib

Id :: distinct int

next :: proc(id: Id) -> Id {
	return id + 1
}
