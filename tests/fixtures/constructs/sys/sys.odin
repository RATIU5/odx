package sys

import "core:os"

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
	abs :: proc(x: i32) -> i32 ---
}

Pair :: struct {
	y: int,
}

quit :: proc(x: i32) {
	p := Pair{1}
	os.exit(int(abs(x)) + p.y)
}
