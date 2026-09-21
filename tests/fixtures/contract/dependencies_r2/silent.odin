#+vet explicit-allocators
package dependencies_r2

import "core:strings"

upper :: proc(s: string, allocator := context.allocator) -> string {
	return strings.to_upper(s, allocator)
}
