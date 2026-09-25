package odx

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"

USAGE :: "usage: odx check [--json]"

main :: proc() {
	arena: virtual.Arena
	if virtual.arena_init_growing(&arena) != nil {
		_, _ = os.write_string(os.stderr, "odx: out of memory\n")
		os.exit(2)
	}
	context.allocator = virtual.arena_allocator(&arena)

	out, err: strings.Builder
	code := run(os.args[1:], ".", &out, &err)
	_, _ = os.write_string(os.stdout, strings.to_string(out))
	_, _ = os.write_string(os.stderr, strings.to_string(err))
	virtual.arena_destroy(&arena) // os.exit skips defers
	os.exit(code)
}

// run executes one odx command against the repository at root and returns the exit code.
// It allocates with context.allocator and frees nothing; the caller owns that lifetime.
run :: proc(args: []string, root: string, out, err: ^strings.Builder) -> int {
	if len(args) == 0 {
		fmt.sbprintln(err, USAGE)
		return 2
	}
	switch args[0] {
	case "help", "--help":
		fmt.sbprintln(out, USAGE)
		return 0
	case "check":
		as_json := false
		for a in args[1:] {
			if a != "--json" {
				fmt.sbprintfln(err, "odx: unknown flag %q", a)
				fmt.sbprintln(err, USAGE)
				return 2
			}
			as_json = true
		}
		return check(root, as_json, out, err)
	}
	fmt.sbprintfln(err, "odx: unknown command %q", args[0])
	fmt.sbprintln(err, USAGE)
	return 2
}

check :: proc(root: string, as_json: bool, out, err: ^strings.Builder) -> int {
	r: Report
	if _, reason := load_config(root); reason != "" {
		append(&r.errors, fmt.aprintf("odx.json: %s", reason))
	}
	finish(&r)
	if as_json {
		write_json(r, out)
	} else {
		write_text(r, out, err)
	}
	return exit_code(r)
}
