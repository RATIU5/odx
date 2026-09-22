package odx

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// Fixture project findings are compared in both directions
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

@(test)
test_fixture_projects_and_rule_examples :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root := find_root("")
	if !testing.expect(t, root != "", "run tests from the repository root") {return}
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
	for id in ([]string{"library/R1", "library/R2"}) {
		failed += check_rule_blocks(join({root, "examples", "policies", "minimal"}), id)
	}
	failed += check_rule_blocks(join({root, "examples", "policies", "strict"}), "")
	testing.expect_value(t, failed, 0)
}

@(test)
test_builtin_example_projects :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root := find_root("")
	p := load_project(root)
	for &topic in p.rb.topics {
		example := Project{root = join({root, "rules", topic.name, "example"}), rb = p.rb}
		example.cfg = exemplar_config(&topic, &p.cfg)
		validate_project(&example)
		testing.expect_value(t, len(example.errs), 0)
		c := make_ctx(&example, nil, {topic.name})
		testing.expect_value(t, run_checks(&c, Analysis_Options{topics = {topic.name}}), 0)
		testing.expect(t, c.r.coverage.complete)
	}
}

// check_rule_blocks: a rule's `fires` must produce that rule and no other finding, its
// `silent` nothing; every fires/silent block in topic.md (the reader checks) must compile and
// produce nothing. Each block is a one-file package (prelude as a sibling) under a scratch
// project assigned the rule's `role` (edge for topic blocks). Effective policy is
// retained; an explicitly tested rule is enabled even if project-disabled.
// only narrows to one "topic/Rn"; "" runs them all.
check_rule_blocks :: proc(root: string, only: string) -> (failed: int) {
	p := load_project(root)
	if len(p.errs) > 0 {
		for e in p.errs {fmt.println("  config:", e)}
		return len(p.errs)
	}
	for t in p.rb.topics {
		for r in t.rules {
			if r.retired {continue}
			id := strings.concatenate({t.name, "/", r.id}, context.temp_allocator)
			if only != "" && id != only {continue}
			for block, which in ([]string{r.fires, r.silent}) {
				name := "fires" if which == 0 else "silent"
				if block == "" {
					fmt.printfln("FAIL %s: missing %s block", id, name)
					failed += 1
					continue
				}
				bad := run_block(&p, r.role, r.prelude, block, id if which == 0 else "", id)
				fmt.printfln("%s %s %s", "ok  " if bad == 0 else "FAIL", id, name)
				failed += bad
			}
		}
		if only != "" {continue}
		for block, i in t.blocks {
			bad := run_block(&p, "edge", "", block, "")
			fmt.printfln("%s %s/topic.md block %d", "ok  " if bad == 0 else "FAIL", t.name, i + 1)
			failed += bad
		}
	}
	return
}

// expect is the one rule id the block must produce; "" means it must be clean.
@(private = "file")
run_block :: proc(
	base: ^Project,
	role, prelude, block, expect: string,
	target := "",
) -> (
	bad: int,
) {
	tmp, terr := os.make_directory_temp("", "odx-rule-*", context.allocator)
	if terr != nil {fail("cannot create temp dir")}
	tmp = canonical(tmp)
	defer os.remove_all(tmp)
	pkg := join({tmp, "sample"})
	os.make_directory_all(pkg)
	// generated names never start with `_` (the compiler skips those)
	write_or_fail(join({pkg, "block.odin"}), block_source(block, "sample"))
	if prelude != "" {write_or_fail(join({pkg, "prelude.odin"}), block_source(prelude, "sample"))}
	cfg := base.cfg
	cfg.default_role = ""
	cfg.exclude = nil
	cfg.roles = make(map[string][]string)
	for name in sorted_keys(base.cfg.roles) {cfg.roles[name] = nil}
	cfg.roles[role] = {"sample"}
	cfg.disabled = make(map[string]string)
	for id, reason in base.cfg.disabled {
		if id != target {cfg.disabled[id] = reason}
	}
	cfg.dependencies = make(map[string]Layer)
	for name, layer in base.cfg.dependencies {cfg.dependencies[name] = layer}
	if role not_in cfg.dependencies {
		cfg.dependencies[role] = {
			may_import = {"core:*", "vendor:*"},
		}
	}
	cfg.odin.collections = make(map[string]string)
	for name, path in base.cfg.odin.collections {
		rel, err := filepath.rel(tmp, canonical(join({base.root, path})))
		if err != nil {fail("cannot resolve example collection %s: %v", name, err)}
		cfg.odin.collections[name] = rel
	}
	sp := Project {
		root = tmp,
		cfg  = cfg,
		rb   = base.rb,
	}
	validate_project(&sp)
	for e in sp.errs {fmt.println("  config:", e)}
	if len(sp.errs) > 0 {return 1}
	c := make_ctx(&sp, nil)
	run_checks(&c, Analysis_Options{})
	hit := false
	for v in c.r.violations {
		if expect != "" && v.rule == expect {
			hit = true
			continue
		}
		fmt.printfln("  unexpected %s:%d: %s %s", v.file, v.line - 1, v.rule, v.message)
		bad += 1
	}
	for e in c.r.tool_errors {
		fmt.println("  tool error:", e)
		bad += 1
	}
	if expect != "" && !hit {
		fmt.printfln("  fires block did not produce %s", expect)
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
	run_checks(&c, Analysis_Options{})
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
