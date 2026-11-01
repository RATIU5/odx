package app

a :: proc(f: f32) -> u32 {
	return transmute(u32)f
}

b :: proc(f: f32) -> i32 {
	return transmute(i32)f
}

c :: proc(s: string) -> []u8 {
	return transmute([]u8)s
}

d :: proc(b: []byte) -> string {
	return transmute(string)b
}

e :: proc(u: u32) -> f32 {
	return transmute(f32)u
}
