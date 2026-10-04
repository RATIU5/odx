#+feature using-stmt
package app

Point :: struct {
	x, y: int,
}

sum :: proc(using p: ^Point) -> int {
	return x + y
}
