package odx

import "core:fmt"
import "core:os"
import "core:strings"

// Exit codes (section 3): 0 clean, 1 violations, 2 tool/config error.
EXIT_VIOLATION :: 1
EXIT_TOOL :: 2

Opts :: struct {
	json:     bool,
	fast:     bool,
	strict:   bool,
	root:     string, // --root override; "" = walk up from cwd
	rule:     string, // explain --rule
	exemplar: string, // check --exemplar <topic>
	topics:   [dynamic]string, // check --topic
	args:     [dynamic]string, // positionals after the subcommand
}

USAGE :: `usage: odx <command> [args] [--json] [--root <dir>]

  topics                       list topics
  explain <topic> [--rule R3]  rules, rationale, do/don't
  for <path>                   topics that apply to a file or package
  check [<path>...] [--topic t] [--fast] [--strict]   run checks (--fast: syntax only)
  ignores                      list every odx:ignore suppression
  ext list | ext validate      project extensions in .odx/ and odx.json5
  init                         write odx.json5 and mise.toml for this project
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
		case "--root", "--rule", "--topic", "--exemplar":
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
	case "check":
		cmd_check(o)
	case "ignores":
		cmd_ignores(o)
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
