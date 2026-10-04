package fx

import "core:fmt"

// odx:ignore line-length top-level decl EXPECT=6,18
Point :: struct {
	x: f32,
	// odx:ignore name-case field with trailing comment EXPECT=9
	Y: f32, // a long trailing comment
	a, b: int,
	// odx:ignore name-case multi-name field EXPECT=12
	C, D: int,
	tag: string `json:"tag"`,
	// odx:ignore line-length nested EXPECT=15,17
	inner: struct {
		z: int,
	},
}

Color :: enum {
	// odx:ignore name-case first member EXPECT=22
	red,
	Green,
}

Shape :: union {
	int,
	// odx:ignore line-length variant EXPECT=29
	f32,
}

Bits :: bit_field u8 {
	// odx:ignore name-case bit field EXPECT=34
	A: u8 | 4,
	b: u8 | 4,
}

// odx:ignore line-length attribute and doc EXPECT=39-41
// A doc comment line.
@(private)
attr_decl :: 1

foreign import libc "system:c"

@(default_calling_convention="c")
foreign libc {
	// odx:ignore name-case foreign member EXPECT=48
	puts :: proc(s: cstring) -> i32 ---
}

g :: proc(
	a: int,
	// odx:ignore name-case param EXPECT=54
	B: int,
) {
	t := []string{
		"short",
		// odx:ignore line-length literal element EXPECT=59
		"https://example.com/a/very/long/url", "second on same line",
	}
	fmt.println(
		"a",
		// odx:ignore line-length call arg EXPECT=64
		"a long argument",
	)
	switch a {
	// odx:ignore line-length case clause EXPECT=68
	case 1:
		fmt.println("one")
	case:
	}
	if a > 0 {
		fmt.println(t)
	// odx:ignore line-length else branch EXPECT=none
	} else {
		fmt.println("no")
	}
	if a > 1 {
		fmt.println("x")
		// odx:ignore line-length end of block EXPECT=none
	}
	// odx:ignore line-length stacked one EXPECT=83-84
	// odx:ignore name-case stacked two EXPECT=84
	y := 1

	// odx:ignore line-length blank line between EXPECT=87-88

	z := 2
	h := proc() {
		// odx:ignore line-length inside proc literal EXPECT=91
		w := 3
		_ = w
	}
	when ODIN_OS == .Darwin {
		// odx:ignore line-length inside when EXPECT=96
		q := 4
		_ = q
	}
	_, _, _ = y, z, h
}
// odx:ignore line-length at eof EXPECT=none
