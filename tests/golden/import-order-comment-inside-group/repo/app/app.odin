package app

import "base:runtime"
// Printing.
import "core:fmt"
import "core:strings"

import "vendor:zlib"

show :: proc() {
	fmt.println(runtime.args__, strings.to_upper("a"), zlib.VERSION)
}
