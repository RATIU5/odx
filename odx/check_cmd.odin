package odx

import "core:fmt"
import "core:os"

// cmd_check: `odx check [<path>...] [--topic t]... [--fast] [--exemplar <topic>]` (17.12).
cmd_check :: proc(o: Opts) {
	p := must_load(o, o.exemplar == "")
	if o.exemplar != "" {
		// CI mode (17.6): the topic's example/ directory is the project.
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
		if len(paths) == 0 {os.exit(0)} 	// nothing changed: nothing to check
	}
	c := make_ctx(&p, paths, o.topics[:])
	code := run_checks(&c, o)
	print_report(c.r, o.json)
	os.exit(code)
}

// run_checks is the whole pipeline (families B, A, C, ignores, stale config) on a context.
run_checks :: proc(c: ^Ctx, o: Opts) -> int {
	full := !o.fast && len(o.topics) == 0 && len(o.args) == 0 // nothing narrowed (20.2)
	run_family_b(c)
	igs := project_ignores(c)
	if !o.fast {
		run_family_a(c)
		run_family_c(c)
	}
	ran := make(map[string]bool, context.temp_allocator)
	for a in c.rules {if !(o.fast && a.rule.check.kind == .require_attribute) {ran[a.id] = true}}
	apply_ignores(c, igs, ran)
	if full {report_stale_config(c)}
	apply_baseline(c, full, o.ci)
	return finalize(c.r, o.strict, o.max_violations)
}

project_ignores :: proc(c: ^Ctx) -> []Ignore {
	igs: [dynamic]Ignore
	for p in c.pkgs {
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
		// the stale set is a byproduct of a full check (M3.3), never a second pass
		run_checks(&c, Opts{})
		for v in c.r.violations {if v.rule == "odx/stale-ignore" {fmt.printfln("%s:%d:%d: %s", v.file, v.line, v.col, v.message)}}
		return
	}
	igs := project_ignores(&c)
	if o.added {igs = added_ignores(p.root, igs)}
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
