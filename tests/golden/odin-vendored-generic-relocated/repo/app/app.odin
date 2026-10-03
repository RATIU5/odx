package app

import "../third_party/dep"

Point :: struct {
	x: int,
}

lower :: proc() -> Point {
	return dep.smaller(Point{1}, Point{2})
}
