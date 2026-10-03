package app

import "core:slice"

S :: struct {
	a: int,
}

lowest :: proc() -> S {
	return slice.min([]S{})
}
