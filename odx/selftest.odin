package odx

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// `odx self-test`: each tests/fixtures/<name>/ project's violations are diffed both ways
// against `// want: topic/R1 other/R2` markers. A package-level violation is satisfied by a
// marker on line 1 of any file in that directory.

Want :: struct {
	file: string, // relative to the fixture root
	line: int,
	rule: string,
	used: bool,
}

FIXTURES_DIR :: "tests/fixtures"
WANT_PREFIX :: "// want:"

cmd_selftest :: proc(o: Opts) {
	root := find_root(o.root)
	if root == "" {fail("no %s found; run from the odx repo", CONFIG_FILE)}
	fixtures := project_subdirs(root, FIXTURES_DIR)
	if len(fixtures) == 0 {fail("no fixtures under %s/%s", root, FIXTURES_DIR)}
	failed := 0
	for e in fixtures {
		if !os.exists(join({e.fullpath, CONFIG_FILE})) {continue}
		bad := run_fixture(e.fullpath)
		fmt.printfln("%s %s/%s", "ok  " if bad == 0 else "FAIL", FIXTURES_DIR, e.name)
		failed += bad
	}
	failed += check_rule_blocks(root, "")
	if failed > 0 {os.exit(EXIT_VIOLATION)}
}

// check_rule_blocks: `fires` must produce that rule and no other finding, `silent` nothing;
// example-only rules must compile both. Each block is a one-file package (prelude as a
// sibling) under a scratch project whose only role is the rule's `role`.
// only narrows to one "topic/Rn"; "" runs them all.
check_rule_blocks :: proc(root: string, only: string) -> (failed: int) {
	p := load_project(root)
	if len(p.errs) > 0 {
		for e in p.errs {fmt.println("  config:", e)}
		return len(p.errs)
	}
	for t in p.rb.topics {
		for r in t.rules {
			if r.retired || (r.fires == "" && r.silent == "") {continue}
			id := strings.concatenate({t.name, "/", r.id}, context.temp_allocator)
			if only != "" && id != only {continue}
			for block, which in ([]string{r.fires, r.silent}) {
				name := "fires" if which == 0 else "silent"
				if block == "" {
					fmt.printfln("FAIL %s: missing %s block", id, name)
					failed += 1
					continue
				}
				bad := run_block(&p, t, r, block, which == 0)
				fmt.printfln("%s %s %s", "ok  " if bad == 0 else "FAIL", id, name)
				failed += bad
			}
		}
	}
	return
}

@(private = "file")
run_block :: proc(base: ^Project, t: Topic, r: Rule, block: string, fires: bool) -> (bad: int) {
	tmp, terr := os.make_directory_temp("", "odx-rule-*", context.allocator)
	if terr != nil {fail("cannot create temp dir")}
	defer os.remove_all(tmp)
	pkg := join({tmp, "sample"})
	os.make_directory_all(pkg)
	// generated names never start with `_` (the compiler skips those)
	write_or_fail(join({pkg, "block.odin"}), block_source(block, "sample"))
	if r.prelude !=
	   "" {write_or_fail(join({pkg, "prelude.odin"}), block_source(r.prelude, "sample"))}
	cfg := fmt.tprintf(
		`{{ version: 1, roles: {{ %q: ["sample"] }}, dependencies: {{ %q: {{ may_import: ["core:*", "vendor:*"] }} }}, odin: {{ flags: ["-vet", "-vet-cast", "-strict-style"] }} }}`,
		r.role,
		r.role,
	)
	write_or_fail(join({tmp, CONFIG_FILE}), cfg)
	sp := load_project(tmp)
	sp.rb = base.rb // the real rulebook, including project topics, not the scratch dir's
	for e in sp.errs {fmt.println("  config:", e)}
	if len(sp.errs) > 0 {return 1}
	c := make_ctx(&sp, nil)
	run_checks(&c, Opts{})
	id := strings.concatenate({t.name, "/", r.id}, context.temp_allocator)
	hit := false
	for v in c.r.violations {
		if v.rule == id && fires && r.check.kind != .example {
			hit = true
			continue
		}
		fmt.printfln(
			"  %s block: unexpected %s:%d: %s %s",
			"fires" if fires else "silent",
			v.file,
			v.line - 1,
			v.rule,
			v.message,
		)
		bad += 1
	}
	for e in c.r.tool_errors {
		fmt.println("  tool error:", e)
		bad += 1
	}
	if fires && r.check.kind != .example && !hit {
		fmt.printfln("  fires block did not produce %s", id)
		bad += 1
	}
	return
}

@(private = "file")
write_or_fail :: proc(path, text: string) {
	if err := os.write_entire_file(path, transmute([]byte)text);
	   err != nil {fail("write %s: %v", path, err)}
}

// run_fixture prints each mismatch.
run_fixture :: proc(dir: string) -> (bad: int) {
	p := load_project(dir)
	if len(p.errs) > 0 {
		for e in p.errs {fmt.println("  config:", e)}
		return len(p.errs)
	}
	c := make_ctx(&p, nil)
	run_checks(&c, Opts{})
	for e in c.r.tool_errors {
		fmt.println("  tool error:", e)
		bad += 1
	}
	wants := collect_wants(dir)
	for v in c.r.violations {
		if w := match_want(wants[:], v); w != nil {
			w.used = true
			continue
		}
		fmt.printfln("  unexpected %s:%d: %s %s", v.file, v.line, v.rule, v.message)
		bad += 1
	}
	for w in wants {
		if !w.used {
			fmt.printfln("  missing    %s:%d: %s", w.file, w.line, w.rule)
			bad += 1
		}
	}
	return
}

match_want :: proc(wants: []Want, v: Violation) -> ^Want {
	for &w in wants {
		if !w.used && w.rule == v.rule && w.file == v.file && w.line == v.line {return &w}
	}
	if strings.has_suffix(v.file, ".odin") {return nil}
	for &w in wants {
		dir, _ := filepath.split(w.file)
		if !w.used &&
		   w.rule == v.rule &&
		   w.line == 1 &&
		   strings.trim_suffix(dir, "/") == v.file {return &w}
	}
	return nil
}

// collect_wants reads markers as text, not AST, so files that fail to parse still carry them.
collect_wants :: proc(root: string) -> (out: [dynamic]Want) {
	w := os.walker_create_path(root)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		if fi.type != .Regular ||
		   !(strings.has_suffix(fi.name, ".odin") || fi.name == CONFIG_FILE) {continue}
		data, err := os.read_entire_file(fi.fullpath, context.allocator)
		if err != nil {fail("%s: cannot read", fi.fullpath)}
		rel, _ := rel_of(root, fi.fullpath)
		for line, i in strings.split_lines(string(data), context.temp_allocator) {
			at := strings.index(line, WANT_PREFIX)
			if at < 0 {continue}
			for rule in strings.fields(line[at + len(WANT_PREFIX):], context.temp_allocator) {
				append(&out, Want{rel, i + 1, rule, false})
			}
		}
	}
	return
}
