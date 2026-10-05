package app

import "core:strings"
import "core:fmt"

shout :: proc(s: string) {
	fmt.println(strings.to_upper(s, context.temp_allocator))
}
