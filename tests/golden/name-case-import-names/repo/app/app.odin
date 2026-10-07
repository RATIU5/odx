package app

import Fmt "core:fmt"
import str "core:strings"

import "vendor:OpenGL"

foreign import LibC "system:c"
foreign import libm "system:m"

VERSION :: OpenGL.VERSION

foreign LibC {
	getpid :: proc() -> i32 ---
}

foreign libm {
	sqrt :: proc(x: f64) -> f64 ---
}

show :: proc(s: string) {
	Fmt.println(str.to_upper(s, context.temp_allocator))
}
