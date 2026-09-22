package odx

import "core:fmt"
import "core:os"

cmd_check :: proc(o: Opts) {
	p := must_load(o, o.exemplar == "")
	if o.exemplar != "" {
		t := find_topic(&p.rb, o.exemplar)
		if t == nil {fail("unknown topic %q", o.exemplar)}
		if p.root == "" {p.root, _ = os.get_working_directory(context.allocator)}
		p.root = join({p.root, "rules", o.exemplar, "example"})
		p.cfg = exemplar_config(t, &p.cfg)
		p.dirs = package_dirs(p.root, &p.cfg)
	}
	for t in o.topics {if find_topic(&p.rb, t) == nil {fail("unknown topic %q", t)}}
	paths := o.args[:]
	if o.since != "" {
		in_git: bool
		paths, in_git = changed_odin_files(p.root, o.since)
		if !in_git {fail("--since needs a git worktree")}
		if len(paths) == 0 {
			c := Ctx {
				root = p.root,
				cfg  = &p.cfg,
				rb   = &p.rb,
				r    = new(Report),
			}
			init_coverage(&c, o)
			code := finalize(c.r, o.strict)
			print_report(c.r, o.json)
			os.exit(code)
		}
	}
	c := make_ctx(&p, paths, o.topics[:])
	code := run_checks(&c, o)
	print_report(c.r, o.json)
	os.exit(code)
}

run_checks :: proc(c: ^Ctx, o: Opts, use_baseline := true) -> int {
	full := !o.fast && len(o.topics) == 0 && len(o.args) == 0 && o.since == ""
	init_coverage(c, o)
	run_family_b(c)
	igs := project_ignores(c)
	if !o.fast {
		run_family_a(c)
		run_family_c(c)
	}
	collect_coverage(c, o)
	ran := make(map[string]bool, context.temp_allocator)
	for a in c.rules {if !(o.fast && is_family_c(a.rule.check.kind)) {ran[a.id] = true}}
	apply_ignores(c, igs, ran)
	source_complete := c.native_ran
	for p in c.pkgs {source_complete &&= p.parse_result.status == .complete}
	if full && source_complete {report_stale_config(c)}
	if use_baseline {apply_baseline(c, full && c.r.coverage.complete, o.ci)}
	refresh_coverage(c.r)
	return finalize(c.r, o.strict, o.max_violations)
}

project_ignores :: proc(c: ^Ctx) -> []Ignore {
	igs: [dynamic]Ignore
	for p in c.pkgs {
		if p.parse_result.status == .failed {continue}
		for f in p.files {
			rel, _ := rel_of(c.root, f.fullpath)
			collect_ignores(c.r, c.rb, f, rel, &igs)
		}
	}
	return igs[:]
}

cmd_ignores :: proc(o: Opts) {
	p := must_load(o, true)
	c := make_ctx(&p, nil)
	if o.stale {
		// the stale set is a byproduct of a full check, never a second pass
		run_checks(&c, Opts{})
		for v in c.r.violations {if v.rule == "odx/stale-ignore" {fmt.printfln("%s:%d:%d: %s", v.file, v.line, v.col, v.message)}}
		return
	}
	igs := project_ignores(&c)
	sort_violations(c.r.violations[:])
	if o.json {
		print_json(struct {
			ignores: []Ignore,
			bad:     []Violation,
		}{igs, c.r.violations[:]})
		return
	}
	for ig in igs {
		scope := "file" if ig.target == 0 else fmt.tprintf("line %d", ig.target)
		fmt.printfln("%s:%d: %s (%s) reason: %s", ig.file, ig.line, ig.rule, scope, ig.reason)
	}
	for v in c.r.violations {fmt.printfln("%s:%d:%d: %s %s", v.file, v.line, v.col, v.rule, v.message)}
	fmt.printfln("%d ignores, %d bad. Not ignorable: odin/*, odx/*", len(igs), len(c.r.violations))
}
