package odx

import "core:fmt"
import "core:io"
import "core:mem/virtual"
import "core:os"

USAGE :: "usage: odx check [--json]"

main :: proc() {
	arena: virtual.Arena
	if virtual.arena_init_growing(&arena) != nil {
		_, _ = os.write_string(os.stderr, "odx: out of memory\n")
		os.exit(2)
	}
	context.allocator = virtual.arena_allocator(&arena)

	code := 2
	// The real absolute root, symlinks resolved; every output path is relative to it.
	if root, err := os.get_absolute_path(".", context.allocator); err != nil {
		fmt.eprintfln("odx: current directory: %s", os.error_string(err))
	} else {
		code = run(os.args[1:], root, os.to_writer(os.stdout), os.to_writer(os.stderr))
	}
	virtual.arena_destroy(&arena) // os.exit skips defers
	os.exit(code)
}

// run executes one odx command against the repository at root, an absolute real path,
// and returns the exit code. It allocates with context.allocator and frees nothing; the
// caller owns that lifetime.
run :: proc(args: []string, root: string, stdout, stderr: io.Writer) -> int {
	if len(args) == 0 {
		fmt.wprintln(stderr, USAGE)
		return 2
	}
	switch args[0] {
	case "help", "--help":
		fmt.wprintln(stdout, USAGE)
		return 0
	case "check":
		as_json := false
		for a in args[1:] {
			if a != "--json" {
				fmt.wprintfln(stderr, "odx: unknown flag %q", a)
				fmt.wprintln(stderr, USAGE)
				return 2
			}
			as_json = true
		}
		return check(root, as_json, stdout, stderr)
	}
	fmt.wprintfln(stderr, "odx: unknown command %q", args[0])
	fmt.wprintln(stderr, USAGE)
	return 2
}

check :: proc(root: string, as_json: bool, stdout, stderr: io.Writer) -> int {
	r: Report
	if cfg, ok := load_config(&r, root); ok {
		_ = cfg // Part 2: package discovery.
	}
	finish(&r)
	if as_json {
		if err := write_json(r, stdout); err != nil {
			// The only output that can say why --json output is missing.
			fmt.wprintfln(stderr, "odx: writing JSON output: %v", err)
			return 2
		}
	} else if write_text(r, stdout, stderr) != nil {
		return 2
	}
	return exit_code(r)
}
