package odx

import "core:fmt"
import "core:os"
import "core:strings"

// Exit codes (section 3): 0 clean, 1 violations, 2 tool/config error.
EXIT_VIOLATION :: 1
EXIT_TOOL :: 2

Opts :: struct {
	json: bool,
	root: string, // --root override; "" = walk up from cwd
	rule: string, // explain --rule
	args: [dynamic]string, // positionals after the subcommand
}

USAGE :: `usage: odx <command> [args] [--json] [--root <dir>]

  topics                       list topics
  explain <topic> [--rule R3]  rules, rationale, do/don't
  for <path>                   topics that apply to a file or package
  ext list | ext validate      project extensions in .odx/ and odx.json5
  init                         write odx.json5 and mise.toml for this project
`

fail :: proc(f: string, args: ..any) -> ! {
	fmt.eprint("odx: ")
	fmt.eprintfln(f, ..args)
	os.exit(EXIT_TOOL)
}

parse_opts :: proc(args: []string) -> (o: Opts) {
	// ponytail: hand-rolled; core:flags has no subcommand concept (17.20)
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		switch {
		case a == "--json":
			o.json = true
		case a == "--root" || a == "--rule":
			if i + 1 >= len(args) {fail("%s needs a value", a)}
			i += 1
			if a == "--root" {o.root = args[i]} else {o.rule = args[i]}
		case strings.has_prefix(a, "--root="):
			o.root = a[len("--root="):]
		case strings.has_prefix(a, "--rule="):
			o.rule = a[len("--rule="):]
		case strings.has_prefix(a, "-"):
			fail("unknown flag %s", a)
		case:
			append(&o.args, a)
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
