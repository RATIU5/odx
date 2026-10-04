package app

f :: proc() {
	// odx:ignore odin the type error is deliberate
	x: int = "text"
	_ = x
	y := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	_ = y
}
