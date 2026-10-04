package app

bytes :: proc(s: string) -> []u8 {
	// odx:ignore transmute a string viewed as bytes without a copy
	return transmute([]u8)s
}
