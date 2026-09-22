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
	ci:             bool, // doctor: version drift is an error
	checklist:      bool,
	max_violations: int,
	hooks:          bool,
	brief:          bool,
	emit:           bool, // for --emit-claude-md
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
  --json is supported on check, doctor, for, explain and ignores; check schema: 1.
  Check exits: 0 no unbaselined errors (warnings fail with --strict), 1 violations, 2 tool/config error.
  Inspect coverage independently: exit 0 does not establish complete analysis.

  check [<path>...] [--topic t] [--fast] [--strict] [--since <ref>] [--ci] [--max-violations N]   run checks (odx.baseline softens, never hides)
  check --exemplar <topic>     check rules/<topic>/example/ against that topic (the exemplars CI task)
  baseline add | regen         freeze current violations into odx.baseline (shrinks on its own; never grows from check)
  for <path> [--brief]         the rules that apply to a file or package (--brief: topic names only)
  for --emit-md [<path>]       portable managed Markdown (--emit-claude-md is an alias)
  guidance check|write <markdown-file> [<package-path>]   check freshness or regenerate the owned block; exits 0 current/written, 1 stale/missing, 2 error
  explain [<topic>] [--rule R3]   no topic: list topics; with one: rules, rationale, do/don't
  explain [<topic>] --checklist   the reader checks from topic.md, for an adversarial reviewer
  ignores [--stale]            every odx:ignore suppression; --stale: suppressing nothing
  doctor [--ci]                toolchain, flags, config errors, mise.toml drift
  hook edit                    Claude Code PostToolBatch hook: reads the hook JSON on stdin, reports, exits 0
  init [--hooks]               write odx.json5 and mise.toml (--hooks: .claude/settings.json, CLAUDE.md)
  self-test                    run every tests/fixtures/* and diff its // want: markers
  rule try '<check json5>' [<path>...] [--count]   run an inline check spec, print every match (nothing written)
  rule try --file <rule.odx.md> [<path>...]        dry-run a drafted rule file the same way
  rule add <topic> [--id R9]   scaffold <topic>/<id>.odx.md with the next free id
  rule test <topic>/<id>       compile just that rule's fires/silent blocks
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
		case "--checklist":
			o.checklist = true
		case "--hooks":
			o.hooks = true
		case "--emit-claude-md", "--emit-md":
			o.emit = true
		case "--brief":
			o.brief = true
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
	case "guidance":
		cmd_guidance(o)
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
