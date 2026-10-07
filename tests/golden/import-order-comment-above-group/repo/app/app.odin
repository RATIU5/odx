package app

import "base:runtime"
import "core:fmt"

// Why zlib.
// It is the only inflate we ship.
import "vendor:zlib"

show :: proc() {
	fmt.println(runtime.args__, zlib.VERSION)
}
