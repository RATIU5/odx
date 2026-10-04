package app

import "core:strings"
import mine "../strings"

shout :: proc(s: string) -> string {
	return mine.to_upper(strings.to_upper(s, context.temp_allocator))
}
