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
	dir := join({root, FIXTURES_DIR})
	entries, rerr := os.read_all_directory_by_path(dir, context.allocator)
	if rerr != nil {fail("%s: cannot read", dir)}
	names := make([dynamic]string)
	for e in entries {if e.type == .Directory && os.exists(join({e.fullpath, CONFIG_FILE})) {append(&names, e.name)}}
	if len(names) == 0 {fail("no fixtures under %s", dir)}
	failed := 0
	for name in names {
		bad := run_fixture(join({dir, name}))
		fmt.printfln("%s %s/%s", "ok  " if bad == 0 else "FAIL", FIXTURES_DIR, name)
		failed += bad
	}
	failed += check_templates(root)
	if failed > 0 {os.exit(EXIT_VIOLATION)}
}

// check_templates renders each template as `Sample` into a temp project with a generated
// odx.json5 and runs the full check there (17.16). api/ snapshots are verified per fixture too.
check_templates :: proc(root: string) -> (failed: int) {
	errs: [dynamic]string
	for &t in load_templates(root, &errs) {
		tmp, terr := os.make_directory_temp("", "odx-tpl-*", context.allocator)
		if terr != nil {fail("cannot create temp dir")}
		defer os.remove_all(tmp)
		cfg := strings.concatenate(
			{
				`{ version: 1, roles: { `,
				t.role,
				`: ["sample"] }, layering: { `,
				t.role,
				`: { may_import: ["core:*"] } }, odin: { flags: ["-vet", "-vet-tabs", "-vet-cast", "-strict-style", "-warnings-as-errors"] } }`,
			},
			context.temp_allocator,
		)
		if err := os.write_entire_file(join({tmp, CONFIG_FILE}), cfg);
		   err != nil {fail("write: %v", err)}
		render_template(&t, "Sample", tmp)
		p := load_project(tmp)
		bad := len(p.errs)
		for e in p.errs {fmt.println("  config:", e)}
		if bad == 0 {
			r, code := run_checks(&p, Opts{})
			fmt.print(report_text(r))
			for e in r.tool_errors {fmt.println("  tool error:", e)}
			if code != 0 {bad += 1}
		}
		fmt.printfln("%s template %s", "ok  " if bad == 0 else "FAIL", t.name)
		failed += bad
	}
	for e in errs {
		fmt.println("  template:", e)
		failed += 1
	}
	return
}

// run_fixture returns the number of mismatches, printing each one.
run_fixture :: proc(dir: string) -> (bad: int) {
	p := load_project(dir)
	if len(p.errs) > 0 {
		for e in p.errs {fmt.println("  config:", e)}
		return len(p.errs)
	}
	r, _ := run_checks(&p, Opts{})
	for e in r.tool_errors {
		fmt.println("  tool error:", e)
		bad += 1
	}
	wants := collect_wants(dir)
	bad += check_fix_pairs(dir, r)
	if os.is_directory(join({dir, API_DIR})) {
		c := Ctx {
			root = dir,
			cfg  = &p.cfg,
			rb   = &p.rb,
			r    = new(Report),
		}
		c.pkgs = project_packages(&p, nil)
		bad += api_snapshots(&c, false)
	}
	for v in r.violations {
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

// collect_wants scans every .odin file under root for `// want:` markers (text, not AST, so
// files that fail to parse still carry expectations).
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

// check_fix_pairs: for every <file>.odin.after in the fixture, `odx fix` on a copy must produce
// it, and running fix again must change nothing (20.1).
check_fix_pairs :: proc(dir: string, r: ^Report) -> (bad: int) {
	afters := make([dynamic]string, context.temp_allocator)
	w := os.walker_create_path(dir)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		if fi.type == .Regular &&
		   strings.has_suffix(fi.name, ".odin.after") {append(&afters, fi.fullpath)}
	}
	if len(afters) == 0 {return}
	tmp, terr := os.make_directory_temp("", "odx-fix-*", context.allocator)
	if terr != nil {fail("cannot create temp dir")}
	defer os.remove_all(tmp)
	copy_tree(dir, tmp)
	// the report's paths are relative, so it applies to the copy unchanged
	apply_fixes(tmp, r, false)
	for after in afters {
		rel, _ := rel_of(dir, strings.trim_suffix(after, ".after"))
		want, _ := os.read_entire_file(after, context.allocator)
		got, _ := os.read_entire_file(join({tmp, rel}), context.allocator)
		if string(want) != string(got) {
			fmt.printfln("  fix %s differs from %s.after", rel, rel)
			bad += 1
		}
	}
	p := load_project(tmp)
	r2, _ := run_checks(&p, Opts{})
	if n := apply_fixes(tmp, r2, true); n > 0 {
		fmt.printfln("  fix is not idempotent: second run would change %d lines", n)
		bad += 1
	}
	return
}

copy_tree :: proc(from, to: string) {
	w := os.walker_create_path(from)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		rel, _ := rel_of(from, fi.fullpath)
		dst := join({to, rel})
		if fi.type == .Directory {
			os.make_directory_all(dst)
		} else if fi.type == .Regular {
			data, _ := os.read_entire_file(fi.fullpath, context.allocator)
			os.make_directory_all(filepath.dir(dst))
			if err := os.write_entire_file(dst, data); err != nil {fail("write %s: %v", dst, err)}
		}
	}
}
