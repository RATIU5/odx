package app

/* note */
f :: proc(s: []int, y: i64, f: f32, ok: bool) -> i32 {
	if ok {return 0}
	if ok do return 1
	x: i32 = auto_cast y
	switch x {
	case 0:
		fallthrough
	case:
	}
	#no_bounds_check {
		x += i32(s[0])
	}
	return x + transmute(i32)f
}

g :: proc() {
	defer _ = #branch_location
}
