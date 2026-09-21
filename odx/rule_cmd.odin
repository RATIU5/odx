package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

cmd_rule :: proc(o: Opts) {
	if len(o.args) == 0 {fail("usage: odx rule try|add|test ...")}
	switch o.args[0] {
	case "try":
		rule_try(o)
	case "add":
		rule_add(o)
	case "test":
		if len(o.args) < 2 {fail("usage: odx rule test <topic>/<id>")}
		root := find_root(o.root)
		if root == "" {fail("no %s found", CONFIG_FILE)}
		if check_rule_blocks(root, o.args[1]) > 0 {os.exit(EXIT_VIOLATION)}
	case:
		fail("unknown rule subcommand %q (try, add, test)", o.args[0])
	}
}

// rule_try writes nothing; ignores, baseline and stale-config are skipped so the count is raw.
rule_try :: proc(o: Opts) {
	r := new(Rule)
	r.severity = .error
	errs: [dynamic]string
	paths := o.args[1:]
	if o.file != "" {
		data, rerr := os.read_entire_file(o.file, context.allocator)
		if rerr != nil {fail("%s: cannot read", o.file)}
		rf, perr := parse_rule_file(string(data))
		if perr != "" {fail("%s: %s", o.file, perr)}
		obj, ok := unmarshal_json5(rf.frontmatter, r, o.file, RULE_KEYS, &errs)
		if ok {
			spec, _ := obj["check"].(json.Object)
			validate_check(&r.check, spec, o.file, &errs)
		}
	} else {
		if len(o.args) < 2 {fail("usage: odx rule try '<check json5>' [<path>...] [--count]")}
		paths = o.args[2:]
		// bare words are strings, as in the frontmatter: `{ kind: pattern, match: call }`
		if obj, ok := unmarshal_json5(o.args[1], &r.check, "check", CHECK_KEYS, &errs);
		   ok {validate_check(&r.check, obj, "check", &errs)}
	}
	for e in errs {fmt.eprintln("odx:", e)}
	if len(errs) > 0 {os.exit(EXIT_TOOL)}
	if r.id == "" {r.id = "try"}
	r.ignorable = true
	p := must_load(o, true)
	c := make_ctx(&p, paths)
	c.rules = {Active_Rule{strings.concatenate({"try/", r.id}), r}}
	run_family_b(&c)
	if is_family_c(r.check.kind) {run_family_c(&c)}
	print_tool_errors(c.r)
	sort_violations(c.r.violations[:])
	n := 0
	for v in c.r.violations {
		if !strings.has_prefix(v.rule, "try/") {continue} 	// odin/syntax notes are not matches
		n += 1
		if !o.count {fmt.printfln("%s:%d:%d: %s", v.file, v.line, v.col, v.message)}
	}
	fmt.printfln("%d match%s", n, "" if n == 1 else "es")
}

// The evidence bar: a compiler version and a command whose output shows the failure the rule
// prevents (allocators/R1 and errors/R3 are the models). An evidence field nobody can check by
// running something is not evidence; the idiom stays a reader check in topic.md until it is.
RULE_STUB :: `---
id: "@ID@",
statement: "",
why: "",
instead_of: "",
evidence: "", // name the compiler version and the command that reproduces the failure; prose is not evidence
cost: "",
severity: "error",
role: "edge",
check: { kind: "pattern", match: "decl", at: "package_scope", mutable: true },
---

Why this idiom exists, in a paragraph a reader can act on.

` + "```odin prelude\n```\n\n```odin fires\n```\n\n```odin silent\n```\n"

// rule_add: built-in topics live under rules/, project topics under .odx/topics/.
rule_add :: proc(o: Opts) {
	if len(o.args) < 2 {fail("usage: odx rule add <topic> [--id R9]")}
	p := must_load(o, true)
	t := find_topic(&p.rb, o.args[1])
	if t == nil {fail("unknown topic %q (create %s/%s/topic.md first)", o.args[1], PROJECT_TOPICS_DIR, o.args[1])}
	dir := join({p.root, t.source if t.source != "builtin" else join({"rules", t.name})})
	if !os.exists(dir) {fail("%s does not exist; built-in topics can only be extended inside the odx repo", dir)}
	id := o.id
	if id == "" {
		hi := 0
		for r in t.rules {
			if n, ok := strconv.parse_int(strings.trim_prefix(r.id, "R")); ok && n > hi {hi = n}
		}
		id = fmt.tprintf("R%d", hi + 1)
	}
	path := join({dir, strings.concatenate({id, RULE_SUFFIX})})
	if os.exists(path) {fail("%s already exists", path)}
	// ponytail: not tprintf, the stub's braces are JSON5 not format verbs
	stub, _ := strings.replace_all(RULE_STUB, "@ID@", id, context.temp_allocator)
	if err := os.write_entire_file(path, transmute([]byte)stub); err != nil {fail("write %s: %v", path, err)}
	fmt.printfln("wrote %s; fill the frontmatter and blocks, then `odx rule test %s/%s`", path, t.name, id)
}
