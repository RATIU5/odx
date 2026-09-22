package odx

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_compiler_rejects_retired_constructs :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	cfg := default_config()
	root := join({find_root(""), "tests", "compiler"})
	w := os.walker_create_path(root)
	defer os.walker_destroy(&w)
	checked := 0
	for file in os.walker_walk(&w) {
		if file.type != .Regular || !strings.has_suffix(file.name, ".odin") {continue}
		state, _, stderr, err := os.process_exec({command = {odin_exe(&cfg), "check", file.fullpath, "-file", "-no-entry-point"}}, context.allocator)
		testing.expect(t, err == nil && state.exit_code != 0 && len(stderr) > 0, fmt.tprintf("compiler must reject %s without extra flags", file.name))
		checked += 1
	}
	testing.expect(t, checked > 0)
}
