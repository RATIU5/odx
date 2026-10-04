package app

f :: proc(n: int) {
	if n > 0 {
		x := "short"
		_ = x
	// odx:ignore line-length meant for the else branch
	} else { // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
		y := "short"
		_ = y
	}
}
