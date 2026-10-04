package app

bits :: proc(f: f32) -> u32 {
	return transmute(u32)f
}

bytes :: proc(s: string) -> []u8 {
	return transmute([]u8)s
}

text :: proc(b: []byte) -> string {
	return transmute(string)b
}
