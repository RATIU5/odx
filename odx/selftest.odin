package odx

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// `odx self-test`: every tests/fixtures/<name>/ with an odx.json5 is checked as a project and
// its violations are diffed both ways against `// want: topic/R1 other/R2` markers (17.14).
// A package-level violation (file is a directory) is satisfied by a marker on line 1 of any
// file in that directory.

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
	if failed > 0 {os.exit(EXIT_VIOLATION)}
}

// run_fixture returns the number of mismatches, printing each one.
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

// collect_wants scans every .odin file (and odx.json5) under root for `// want:` markers.
// Text, not AST, so files that fail to parse still carry expectations.
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
