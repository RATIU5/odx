package odx

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

EXIT_VIOLATION :: 1
EXIT_TOOL :: 2

Opts :: struct {
	json, fast, strict, checklist, stale: bool,
	max_violations: int,
	root, since, rule, write, verify: string,
	topics, args: [dynamic]string,
}

USAGE :: `usage: odx <command> [args] [--json] [--root <dir>]

  check [paths...] [--topic NAME] [--fast] [--strict] [--since REF]
        [--max-violations N]     findings and evidence coverage
  policy [path] [--topic NAME] [--rule ID] [--checklist]
         [--write FILE | --verify FILE]   applicable policy and managed instructions
  baseline add|prune|regen       explicitly maintain accepted findings
  ignores [--stale]              list suppressions or audit their validity

All commands support --json (schema 2). No model calls or implicit file writes.
Check exits: 0 no failing findings, 1 findings, 2 tool/config error.
Warnings fail with --strict. Inspect coverage even when exit is 0.
Policy --verify exits 0 current, 1 stale/missing, 2 error.
`

// Set before parsing, so even malformed arguments have structured errors.
machine_output: bool

fail :: proc(f: string, args: ..any) -> ! {
	message := fmt.aprintf(f, ..args)
	if machine_output {
		r: Report
		tool_error(&r, "%s", message)
		finalize(&r, false)
		print_report(&r, true)
	} else {
		fmt.eprintfln("odx: %s", message)
	}
	os.exit(EXIT_TOOL)
}

command_flags :: proc(command: string) -> []string {
	switch command {
	case "check": return slice.clone([]string{"--fast", "--strict", "--since", "--topic", "--max-violations"}, context.temp_allocator)
	case "policy": return slice.clone([]string{"--topic", "--rule", "--checklist", "--write", "--verify"}, context.temp_allocator)
	case "baseline": return nil
	case "ignores": return slice.clone([]string{"--stale"}, context.temp_allocator)
	}
	fail("unknown command %q; use `odx help`", command)
}

parse_opts :: proc(command: string, args: []string) -> (o: Opts) {
	allowed := command_flags(command)
	positionals := false
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		if a == "--" && !positionals {positionals = true; continue}
		if positionals || !strings.has_prefix(a, "-") {append(&o.args, a); continue}
		name, equals, value := strings.partition(a, "=")
		if name != "--json" && name != "--root" && !slice.contains(allowed, name) {
			fail("%s does not accept %s; use `odx help`", command, name)
		}
		switch name {
		case "--json", "--fast", "--strict", "--checklist", "--stale":
			if equals != "" {fail("%s does not take a value", name)}
			switch name {
			case "--json": o.json = true
			case "--fast": o.fast = true
			case "--strict": o.strict = true
			case "--checklist": o.checklist = true
			case "--stale": o.stale = true
			}
		case:
			if equals == "" {
				if i + 1 >= len(args) {fail("%s needs a value", name)}
				i += 1
				value = args[i]
			}
			if value == "" || strings.has_prefix(value, "--") {fail("%s needs a nonempty value", name)}
			switch name {
			case "--root": o.root = value
			case "--since": o.since = value
			case "--rule": o.rule = value
			case "--write": o.write = value
			case "--verify": o.verify = value
			case "--topic": append(&o.topics, value)
			case "--max-violations":
				n, ok := strconv.parse_int(value)
				if !ok || n < 0 {fail("--max-violations needs a non-negative integer")}
				o.max_violations = n
			}
		}
	}
	return
}

main :: proc() {
	for a in os.args[1:] {
		if a == "--" {break}
		if a == "--json" || strings.has_prefix(a, "--json=") {machine_output = true}
	}
	if len(os.args) < 2 {fail("a command is required; use `odx help`")}
	command := os.args[1]
	if command == "help" || command == "--help" || command == "-h" {
		if machine_output {print_json(struct {schema: int, usage: string}{2, USAGE})} else {fmt.print(USAGE)}
		return
	}
	o := parse_opts(command, os.args[2:])
	switch command {
	case "check": cmd_check(o)
	case "policy": cmd_policy(o)
	case "baseline": cmd_baseline(o)
	case "ignores":
		if len(o.args) != 0 {fail("usage: odx ignores [--stale]")}
		cmd_ignores(o)
	}
}
