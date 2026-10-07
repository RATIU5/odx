package app

import "base:runtime"
// Detached.

import "core:fmt"
// Compression.
import "vendor:zlib"

show :: proc() {
	fmt.println(runtime.args__, zlib.VERSION)
}
