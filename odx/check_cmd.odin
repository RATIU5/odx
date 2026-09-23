package odx

import "core:fmt"
import "core:os"

analysis_options :: proc(o: Opts) -> Analysis_Options {
	return {
		root = o.root,
		paths = o.args[:],
		topics = o.topics[:],
		since = o.since,
		fast = o.fast,
		strict = o.strict,
		max_violations = o.max_violations,
	}
}

cmd_check :: proc(o: Opts) {
	r, code := analyze(analysis_options(o))
	print_report(r, o.json)
	os.exit(code)
}

cmd_ignores :: proc(o: Opts) {
	p := must_load(o, true)
	c := make_ctx(&p, nil)
	if o.stale {
		run_checks(&c, Analysis_Options{}, use_baseline = false)
		code := 0
		for v in c.r.violations {
			if v.rule == "odx/stale-ignore" || v.rule == "odx/bad-ignore" {code = EXIT_VIOLATION}
		}
		if !c.r.coverage.complete || len(c.r.tool_errors) > 0 {code = EXIT_TOOL}
		print_report(c.r, o.json)
		os.exit(code)
	}
	for pkg in c.pkgs {
		if pkg.parse_result.status == .failed {
			tool_error(
				c.r,
				"cannot list ignores in %s: %s",
				pkg.rel if pkg.rel != "" else ".",
				pkg.parse_result.reason,
			)
		}
	}
	if len(c.r.tool_errors) > 0 {
		code := finalize(c.r, c.rb, false)
		print_report(c.r, o.json)
		os.exit(code)
	}
	igs := project_ignores(&c)
	sort_violations(c.r.violations[:])
	if o.json {
		print_json(struct {
			schema:  int,
			ignores: []Ignore,
			bad:     []Violation,
		}{2, igs, c.r.violations[:]})
		return
	}
	for ig in igs {
		scope := "file" if ig.target == 0 else fmt.tprintf("line %d", ig.target)
		fmt.printfln("%s:%d: %s (%s) reason: %s", ig.file, ig.line, ig.rule, scope, ig.reason)
	}
	for v in c.r.violations {fmt.printfln("%s:%d:%d: %s %s", v.file, v.line, v.col, v.rule, v.message)}
	fmt.printfln("%d ignores, %d bad. Not ignorable: odin/*, odx/*", len(igs), len(c.r.violations))
}

must_load :: proc(o: Opts, need_config: bool) -> Project {
	p := load_project(o.root)
	if need_config && p.root == "" {
		errf(&p.errs, "no %s found here or in any parent (use --root)", CONFIG_FILE)
	}
	if len(p.errs) > 0 {
		if o.json {
			r := Report {
				tool_errors = p.errs,
			}
			code := finalize(&r, nil, false)
			print_report(&r, true)
			os.exit(code)
		}
		for e in p.errs {fmt.eprintln("odx:", e)}
		os.exit(EXIT_TOOL)
	}
	return p
}
