#+build darwin
package macos_paths

import "core:strings"

SUPPORT_DIR :: "Library/Application Support"

support_path :: proc(home, app: string, allocator := context.allocator) -> string {
	sep := "/"
	parts := [?]string{home, SUPPORT_DIR, app}
	return strings.join(parts[:], "/", allocator)
}
