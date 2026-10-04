package fx

// odx:ignore line-length struct header EXPECT=4,9
Point :: struct {
	x: f32,
	// odx:ignore name-case one field EXPECT=7
	Y: f32, // trailing
	z: f32,
}

// odx:ignore line-length proc header EXPECT=12-15,19
f :: proc(
	a: int,
	b: int,
) -> int {
	x := 1
	_ = x
	return a + b
}

g :: proc(n: int) {
	// odx:ignore line-length for header EXPECT=23,26
	for i in 0 ..< n {
		y := i
		_ = y
	}
	switch n {
	// odx:ignore line-length case header EXPECT=29
	case 1:
		z := 2
		_ = z
	case 2: _ = 3
	}
	// odx:ignore line-length stacked over the next ignore EXPECT=35-36
	// odx:ignore line-length stmt EXPECT=36
	w := 4
	_ = w
	// odx:ignore line-length literal decl EXPECT=39,42
	t := []string{
		"a",
		"b",
	}
	_ = t
	// odx:ignore line-length if else EXPECT=45,47,49
	if n > 0 {
		w = 1
	} else {
		w = 2
	}
}
