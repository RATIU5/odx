package app

import "vendor:zlib"

VERSION :: zlib.VERSION

import "core:fmt"

foreign import libc "system:c"

import "base:runtime"

show :: proc() {
	fmt.println(runtime.args__, VERSION)
}

foreign libc {
	getpid :: proc() -> i32 ---
}
