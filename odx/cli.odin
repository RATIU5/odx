package odx

import "base:runtime"
import "core:fmt"
import "core:strings"

Check_Command :: struct {
	json:         bool,
	pending:      bool,
	// How many finding lines the text output prints, and 0 for all of them.
	max_findings: int,
}

Init_Command :: struct {}

Format_Child_Command :: struct {
	file: string,
}

Help_Command :: struct {}

Version_Command :: struct {}

Rules_Command :: struct {
	json: bool,
}

Explain_Command :: struct {
	rule: Rule,
	json: bool,
}

FORMAT_COMMAND :: "__format"
HELP_FLAG :: "--help"
VERSION_FLAG :: "--version"
MAX_FINDINGS_FLAG :: "--max-findings"

// Exactly one command, or the `usage` error that explains why there is none.
Parsed_Args :: union {
	Check_Command,
	Init_Command,
	Format_Child_Command,
	Help_Command,
	Version_Command,
	Rules_Command,
	Explain_Command,
	Error,
}

// `args` excludes the program name. A returned error's message is allocated with `allocator`.
parse_args :: proc(args: []string, allocator: runtime.Allocator) -> Parsed_Args {
	if len(args) == 0 {
		return usage(allocator, "no command")
	}
	name, rest := args[0], args[1:]
	switch name {
	case "check":
		cmd: Check_Command
		for i := 0; i < len(rest); i += 1 {
			switch rest[i] {
			case "--json":
				cmd.json = true
			case "--pending":
				cmd.pending = true
			case MAX_FINDINGS_FLAG:
				if cmd.max_findings > 0 {
					return usage(allocator, "'%s' given twice for '%s'", MAX_FINDINGS_FLAG, name)
				}
				if i + 1 == len(rest) {
					return usage(
						allocator,
						"'%s' for '%s' needs a number",
						MAX_FINDINGS_FLAG,
						name,
					)
				}
				i += 1
				n, ok := parse_positive(rest[i])
				if !ok {
					return usage(
						allocator,
						"'%s' for '%s' needs a positive number, not '%s'",
						MAX_FINDINGS_FLAG,
						name,
						rest[i],
					)
				}
				cmd.max_findings = n
			case:
				return bad_arg(allocator, name, rest[i])
			}
		}
		// A capped JSON document would leave out findings its schema promises.
		if cmd.json && cmd.max_findings > 0 {
			return usage(allocator, "'%s' can't be combined with '--json'", MAX_FINDINGS_FLAG)
		}
		return cmd
	case "init":
		if len(rest) > 0 {
			return bad_arg(allocator, name, rest[0])
		}
		return Init_Command{}
	case HELP_FLAG:
		if len(rest) > 0 {
			return bad_arg(allocator, name, rest[0])
		}
		return Help_Command{}
	case VERSION_FLAG:
		if len(rest) > 0 {
			return bad_arg(allocator, name, rest[0])
		}
		return Version_Command{}
	case "rules":
		cmd: Rules_Command
		for arg in rest {
			if arg != "--json" {
				return bad_arg(allocator, name, arg)
			}
			cmd.json = true
		}
		return cmd
	case "explain":
		cmd: Explain_Command
		id := ""
		for arg in rest {
			switch {
			case arg == "--json":
				cmd.json = true
			case id != "" || strings.has_prefix(arg, "-"):
				return bad_arg(allocator, name, arg)
			case:
				id = arg
			}
		}
		if id == "" {
			return usage(allocator, "'%s' needs a rule", name)
		}
		known: bool
		cmd.rule, known = rule_by_id(id)
		if !known {
			return usage(allocator, "unknown rule '%s' for '%s'", id, name)
		}
		return cmd
	case FORMAT_COMMAND:
		if len(rest) == 1 {
			return Format_Child_Command{rest[0]}
		}
	}
	return usage(allocator, "unknown command '%s'", name)
}

// Decimal digits only: `strconv` also takes a sign, `_` separators and a base prefix, and doesn't
// report overflow.
@(private = "file")
parse_positive :: proc(s: string) -> (n: int, ok: bool) {
	if s == "" {
		return
	}
	for i in 0 ..< len(s) {
		c := s[i]
		if c < '0' || c > '9' {
			return
		}
		digit := int(c - '0')
		if n > (max(int) - digit) / 10 {
			return
		}
		n = n * 10 + digit
	}
	return n, n > 0
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
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, format, ..args)
	fmt.sbprintf(&b, "; run 'odx %s'", HELP_FLAG)
	return Error{.Usage, strings.to_string(b)}
}
