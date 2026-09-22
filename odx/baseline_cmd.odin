package odx

import "core:fmt"
import "core:os"

cmd_baseline :: proc(o: Opts) {
	if len(o.args) != 1 ||
	   (o.args[0] != "add" &&
			   o.args[0] != "regen" &&
			   o.args[0] != "prune") {fail("usage: odx baseline add | regen | prune")}
	p := must_load(o, true)
	_, existing, inspect_error := baseline_file(p.root)
	if inspect_error != "" {fail("%s", inspect_error)}
	if existing && o.args[0] == "regen" {
		_, read_error := os.read_entire_file(join({p.root, BASELINE_FILE}), context.temp_allocator)
		if read_error != nil {fail("cannot read %s: %v", BASELINE_FILE, read_error)}
	}
	es: []Baseline_Entry
	if o.args[0] != "regen" {
		previous, _, err := read_baseline(p.root)
		if err != "" {fail("%s", err)}
		es = previous
	}
	c := make_ctx(&p, nil)
	run_checks(&c, Analysis_Options{}, use_baseline = false)
	if !c.r.coverage.complete || len(c.r.tool_errors) > 0 {
		tool_error(c.r, "baseline unchanged: required analysis did not complete")
		print_report(c.r, o.json)
		os.exit(EXIT_TOOL)
	}
	hit := baseline_match(&c, es)
	result := make([dynamic]Baseline_Entry)
	for e, i in es {if o.args[0] != "prune" || hit[i] {append(&result, e)}}
	added := 0
	if o.args[0] != "prune" {
		fingerprints := baseline_fingerprints(&c)
		for v in c.r.violations {
			if v.baselined {continue}
			if r := find_rule(c.rb, v.rule); r == nil || !r.baselineable {continue}
			e, ok := baseline_key(v, fingerprints)
			if ok {append(&result, e); added += 1}
		}
	}
	if err := write_baseline(p.root, result[:]); err != "" {fail("%s", err)}
	if o.json {
		print_json(struct {schema: int, file: string, entries, added: int}{2, BASELINE_FILE, len(result), added})
	} else {
		fmt.printfln("%s: %d entries (%d added)", BASELINE_FILE, len(result), added)
	}
}
