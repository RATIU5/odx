package app

import "core:fmt"
import "vendor:zlib"

show :: proc() {
	fmt.println(zlib.VERSION)
}
