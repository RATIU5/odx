package odx

import "base:runtime"
import "core:fmt"
import "core:strings"

Check_Command :: struct {
	json:    bool,
	pending: bool,
}

Init_Command :: struct {}

// Exactly one command, or the `usage` error that explains why there is none.
Parsed_Args :: union {
	Check_Command,
	Init_Command,
	Error,
}

// `args` excludes the program name. A returned error's message is allocated with `allocator`.
parse_args :: proc(args: []string, allocator: runtime.Allocator) -> Parsed_Args {
	if len(args) == 0 {
		return usage(allocator, "no command; run 'odx check' or 'odx init'")
	}
	name, rest := args[0], args[1:]
	switch name {
	case "check":
		cmd: Check_Command
		for arg in rest {
			switch arg {
			case "--json":
				cmd.json = true
			case "--pending":
				cmd.pending = true
			case:
				return bad_arg(allocator, name, arg)
			}
		}
		return cmd
	case "init":
		if len(rest) > 0 {
			return bad_arg(allocator, name, rest[0])
		}
		return Init_Command{}
	}
	return usage(allocator, "unknown command '%s'", name)
}

@(private = "file")
bad_arg :: proc(allocator: runtime.Allocator, command, arg: string) -> Error {
	if strings.has_prefix(arg, "-") {
		return usage(allocator, "unknown flag '%s' for '%s'", arg, command)
	}
	return usage(allocator, "unexpected argument '%s' for '%s'", arg, command)
}

@(private = "file")
usage :: proc(allocator: runtime.Allocator, format: string, args: ..any) -> Error {
	return Error{.Usage, fmt.aprintf(format, ..args, allocator = allocator)}
}
