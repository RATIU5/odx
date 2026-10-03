package app

import "../wrap"

Point :: struct {
	x: int,
}

lowest :: proc() -> Point {
	return wrap.smallest([]Point{})
}
