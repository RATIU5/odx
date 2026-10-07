package app

area :: proc(r: int) -> int {
	scale :: 3
	SCALE :: 3
	point :: struct {
		x: int,
	}
	Point :: struct {
		x: int,
	}
	a := point{r}
	b := Point{r}
	return a.x * scale + b.x * SCALE
}
