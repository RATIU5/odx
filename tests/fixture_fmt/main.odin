// Rewrites Odin files with the printer and config that odx's `format` rule checks against. It
// prints each file once, as odinfmt does, so a file that a second print changes needs a second run.
// This is a test tool for odx's own sources and golden fixtures. odx itself never rewrites code.
// Usage: fixture-fmt <path>... Each path is a file, or a directory whose own `.odin` files are
// formatted. Subdirectories are left alone, which is how `mise run fmt` skips `odx/ols_printer`.
package fixture_fmt

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"

import "../../odx"

main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	if len(os.args) < 2 {
		fmt.eprintln("usage: fixture-fmt <path>...")
		return 2
	}
	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	failed := false
	for path in os.args[1:] {
		if !os.is_directory(path) {
			failed |= !format_file(path)
			virtual.arena_free_all(&arena)
			continue
		}
		entries, err := os.read_directory_by_path(path, -1, context.temp_allocator)
		if err != nil {
			fmt.eprintfln("fixture-fmt: %s: %s", path, os.error_string(err))
			failed = true
			continue
		}
		slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
		for entry in entries {
			if entry.type == .Regular && strings.has_suffix(entry.name, ".odin") {
				failed |= !format_file(entry.fullpath)
				virtual.arena_free_all(&arena)
			}
		}
	}
	return 1 if failed else 0
}

// Works in `context.allocator`, which the caller resets after each file.
format_file :: proc(path: string) -> (ok: bool) {
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("fixture-fmt: %s: %s", path, os.error_string(read_err))
		return false
	}
	out, printed := odx.print_source(string(data))
	if !printed {
		fmt.eprintfln("fixture-fmt: %s: the formatter can't read the file", path)
		return false
	}
	if out == string(data) {
		return true
	}
	if write_err := os.write_entire_file(path, out); write_err != nil {
		fmt.eprintfln("fixture-fmt: %s: %s", path, os.error_string(write_err))
		return false
	}
	fmt.printfln("formatted %s", path)
	return true
}
