package odx

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Exit codes: 0 clean, 1 violations, 2 tool/config error.
EXIT_VIOLATION :: 1
EXIT_TOOL :: 2

Opts :: struct {
	json:           bool,
	fast:           bool,
	strict:         bool,
	ci:             bool, // doctor: version drift is an error, lock is verified
	verify:         bool, // doctor --verify-rulebook
	relock:         bool,
	checklist:      bool,
	max_violations: int,
	hooks:          bool,
	brief:          bool,
	report:         bool,
	added:          bool,
	stale:          bool,
	count:          bool,
	file:           string,
	id:             string,
	since:          string,
	root:           string, // --root override; "" = walk up from cwd
	rule:           string,
	exemplar:       string,
	topics:         [dynamic]string,
	args:           [dynamic]string, // positionals after the subcommand
}

USAGE :: `usage: odx <command> [args] [--json] [--root <dir>]

  check [<path>...] [--topic t] [--fast] [--strict] [--since <ref>] [--ci]   run checks (odx.baseline softens, never hides)
  baseline add | regen         freeze current violations into odx.baseline (shrinks on its own; never grows from check)
  for <path> [--brief]         the rules that apply to a file or package (--brief: topic names only)
  explain [<topic>] [--rule R3]   no topic: list topics; with one: rules, rationale, do/don't
  explain [<topic>] --checklist   example-only rules, for an adversarial reviewer
  ignores [--added] [--stale]  every odx:ignore suppression; --added: not in HEAD; --stale: suppressing nothing
  doctor [--ci] [--verify-rulebook | --relock]   toolchain, flags, config errors, mise.toml drift, lock
  hook edit | stop | changed   Claude Code hook entry points (read the hook JSON on stdin)
  init [--hooks]               write odx.json5 and mise.toml (--hooks: .claude/settings.json, CLAUDE.md)
  self-test                    run every tests/fixtures/* and diff its // want: markers
  rule try '<check json5>' [<path>...] [--count]   run an inline check spec, print every match (nothing written)
  rule try --file <rule.odx.md> [<path>...]        dry-run a drafted rule file the same way
  rule add <topic> [--id R5]   scaffold <topic>/<id>.odx.md with the next free id
  rule test <topic>/<id>       compile just that rule's fires/silent blocks
  eval [<task>...] [--topic bare|for|hook] [--report]   M6 pilot: run evals/<task>/ through claude -p and score mechanically
`

fail :: proc(f: string, args: ..any) -> ! {
	fmt.eprint("odx: ")
	fmt.eprintfln(f, ..args)
	os.exit(EXIT_TOOL)
}

// ponytail: hand-rolled; core:flags has no subcommand concept
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
		case "--report":
			o.report = true
		case "--brief":
			o.brief = true
		case "--added":
			o.added = true
		case "--stale":
			o.stale = true
		case "--count":
			o.count = true
		case "--max-violations":
			if has_eq == "" {
				if i + 1 >= len(args) {fail("%s needs a value", a)}
				i += 1
				value = args[i]
			}
			n, ok := strconv.parse_int(value)
			if !ok || n < 0 {fail("--max-violations needs a non-negative integer")}
			o.max_violations = n
		case "--root", "--rule", "--topic", "--exemplar", "--since", "--file", "--id":
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
			case "--file":
				o.file = value
			case "--id":
				o.id = value
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
	case "eval":
		cmd_eval(o)
	case "self-test":
		cmd_selftest(o)
	case "rule":
		cmd_rule(o)
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
