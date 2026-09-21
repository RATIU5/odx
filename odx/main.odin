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
	dry_run:        bool, // fix --propose
	max_violations: int,
	allow_dirty:    bool, // fix --allow-dirty
	hooks:          bool, // init --hooks
	list:           bool, // new --list
	explain:        bool, // ask --explain
	eval:           bool, // ask --eval
	dir:            string, // new --dir
	root:           string, // --root override; "" = walk up from cwd
	rule:           string, // explain --rule
	exemplar:       string, // check --exemplar <topic>
	topics:         [dynamic]string, // check --topic
	args:           [dynamic]string, // positionals after the subcommand
}

USAGE :: `usage: odx <command> [args] [--json] [--root <dir>]

  topics                       list topics
  explain <topic> [--rule R3]  rules, rationale, do/don't
  explain [<topic>] --checklist   manual rules only, for an adversarial reviewer
  for <path>                   topics that apply to a file or package
  ask "<question>" [--explain] topics that answer a question (local BM25; --eval: recall@3 over rules/ask-eval.json5)
  check [<path>...] [--topic t] [--fast] [--strict] [--max-violations n]   run checks
  ignores                      list every odx:ignore suppression
  api [<path>...]              public API snapshots in api/<pkg>.txt (ODX_UPDATE_SNAPSHOTS=1 re-blesses)
  new <template> <Name> [--dir d]   scaffold a package from a template (--list: templates)
  doctor [--ci] [--verify-rulebook | --relock]   toolchain, flags, mise.toml drift, protected-path lock
  fix [<path>...] [--propose] [--allow-dirty]    delete stale odx:ignore directives (--propose: print only)
  hook edit | stop | changed   Claude Code hook entry points (read the hook JSON on stdin)
  self-test                    run every tests/fixtures/* and diff its // want: markers
  ext list | ext validate      project extensions in .odx/ and odx.json5
  init [--hooks]               write odx.json5 and mise.toml (--hooks: .claude/settings.json, CLAUDE.md)
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
		case "--propose", "--dry-run":
			o.dry_run = true
		case "--allow-dirty":
			o.allow_dirty = true
		case "--hooks":
			o.hooks = true
		case "--list":
			o.list = true
		case "--explain":
			o.explain = true
		case "--eval":
			o.eval = true
		case "--max-violations":
			if has_eq == "" {
				if i + 1 >= len(args) {fail("%s needs a value", a)}
				i += 1
				value = args[i]
			}
			n, ok := strconv.parse_int(value)
			if !ok || n < 0 {fail("--max-violations needs a non-negative integer")}
			o.max_violations = n
		case "--root", "--rule", "--topic", "--exemplar", "--dir":
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
			case "--dir":
				o.dir = value
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
	case "topics":
		cmd_topics(o)
	case "explain":
		cmd_explain(o)
	case "for":
		cmd_for(o)
	case "ask":
		cmd_ask(o)
	case "check":
		cmd_check(o)
	case "ignores":
		cmd_ignores(o)
	case "doctor":
		cmd_doctor(o)
	case "self-test":
		cmd_selftest(o)
	case "fix":
		cmd_fix(o)
	case "api":
		cmd_api(o)
	case "new":
		cmd_new(o)
	case "hook":
		cmd_hook(o)
	case "ext":
		cmd_ext(o)
	case "init":
		cmd_init(o)
	case "help", "--help", "-h":
		fmt.print(USAGE)
	case:
		fmt.eprintfln("odx: unknown command %q\n%s", os.args[1], USAGE)
		os.exit(EXIT_TOOL)
	}
}
