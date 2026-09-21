package odx

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Exit codes (section 3): 0 clean, 1 violations, 2 tool/config error.
EXIT_VIOLATION :: 1
EXIT_TOOL :: 2

Opts :: struct {
	json:           bool,
	fast:           bool,
	strict:         bool,
	ci:             bool, // doctor: version drift is an error, lock is verified
	verify:         bool, // doctor --verify-rulebook
	relock:         bool, // doctor --relock
	checklist:      bool, // explain --checklist
	max_violations: int,
	hooks:          bool, // init --hooks
	added:          bool, // ignores --added
	stale:          bool, // ignores --stale
	since:          string, // check --since <ref>
	root:           string, // --root override; "" = walk up from cwd
	rule:           string, // explain --rule
	exemplar:       string, // check --exemplar <topic>
	topics:         [dynamic]string, // check --topic
	args:           [dynamic]string, // positionals after the subcommand
}

USAGE :: `usage: odx <command> [args] [--json] [--root <dir>]

  check [<path>...] [--topic t] [--fast] [--strict] [--since <ref>] [--ci]   run checks (odx.baseline softens, never hides)
  baseline add | regen         freeze current violations into odx.baseline (shrinks on its own; never grows from check)
  for <path>                   topics that apply to a file or package
  explain [<topic>] [--rule R3]   no topic: list topics; with one: rules, rationale, do/don't
  explain [<topic>] --checklist   manual rules only, for an adversarial reviewer
  ignores [--added] [--stale]  every odx:ignore suppression; --added: not in HEAD; --stale: suppressing nothing
  doctor [--ci] [--verify-rulebook | --relock]   toolchain, flags, config errors, mise.toml drift, lock
  hook edit | stop | changed   Claude Code hook entry points (read the hook JSON on stdin)
  init [--hooks]               write odx.json5 and mise.toml (--hooks: .claude/settings.json, CLAUDE.md)
  self-test                    run every tests/fixtures/* and diff its // want: markers
`

fail :: proc(f: string, args: ..any) -> ! {
	fmt.eprint("odx: ")
	fmt.eprintfln(f, ..args)
	os.exit(EXIT_TOOL)
}

// parse_opts accepts `--flag`, `--flag value` and `--flag=value`.
// ponytail: hand-rolled; core:flags has no subcommand concept (17.20)
parse_opts :: proc(args: []string) -> (o: Opts) {
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		if !strings.has_prefix(a, "-") {
			append(&o.args, a)
			continue
		}
		name, has_eq, value := strings.partition(a, "=")
		switch name {
		case "--json":
			o.json = true
		case "--fast":
			o.fast = true
		case "--strict":
			o.strict = true
		case "--ci":
			o.ci = true
		case "--verify-rulebook":
			o.verify = true
		case "--relock":
			o.relock = true
		case "--checklist":
			o.checklist = true
		case "--hooks":
			o.hooks = true
		case "--added":
			o.added = true
		case "--stale":
			o.stale = true
		case "--max-violations":
			if has_eq == "" {
				if i + 1 >= len(args) {fail("%s needs a value", a)}
				i += 1
				value = args[i]
			}
			n, ok := strconv.parse_int(value)
			if !ok || n < 0 {fail("--max-violations needs a non-negative integer")}
			o.max_violations = n
		case "--root", "--rule", "--topic", "--exemplar", "--since":
			if has_eq == "" {
				if i + 1 >= len(args) {fail("%s needs a value", a)}
				i += 1
				value = args[i]
			}
			switch name {
			case "--root":
				o.root = value
			case "--rule":
				o.rule = value
			case "--topic":
				append(&o.topics, value)
			case "--exemplar":
				o.exemplar = value
			case "--since":
				o.since = value
			}
		case:
			fail("unknown flag %s", a)
		}
	}
	return
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprint(USAGE)
		os.exit(EXIT_TOOL)
	}
	o := parse_opts(os.args[2:])
	switch os.args[1] {
	case "explain":
		cmd_explain(o)
	case "for":
		cmd_for(o)
	case "check":
		cmd_check(o)
	case "baseline":
		cmd_baseline(o)
	case "ignores":
		cmd_ignores(o)
	case "doctor":
		cmd_doctor(o)
	case "self-test":
		cmd_selftest(o)
	case "hook":
		cmd_hook(o)
	case "init":
		cmd_init(o)
	case "help", "--help", "-h":
		fmt.print(USAGE)
	case:
		fmt.eprintfln("odx: unknown command %q\n%s", os.args[1], USAGE)
		os.exit(EXIT_TOOL)
	}
}
