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
	}
	for t in o.topics {if find_topic(&p.rb, t) == nil {fail("unknown topic %q", t)}}
	r, code := run_checks(&p, o)
	print_report(r, o.json)
	os.exit(code)
}

// run_checks is the whole pipeline (families B, A, C, ignores) on a loaded project; shared by
// `check` and `self-test`.
run_checks :: proc(p: ^Project, o: Opts) -> (r: ^Report, code: int) {
	c := Ctx {
		root  = p.root,
		cfg   = &p.cfg,
		rb    = &p.rb,
		r     = new(Report),
		rules = active_rules(p, o.topics[:]),
	}
	c.pkgs = project_packages(p, o.args[:])
	run_family_b(&c)
	igs := project_ignores(&c)
	if !o.fast {
		run_family_a(&c)
		run_family_c(&c)
	}
	ran := make(map[string]bool, context.temp_allocator)
	for a in c.rules {if !(o.fast && a.spec.kind == "require_attribute") {ran[a.id] = true}}
	apply_ignores(c.r, igs, ran)
	if !o.fast && len(o.topics) == 0 && len(o.args) == 0 {report_stale_config(&c)}
	return c.r, finalize(c.r, o.strict, o.max_violations)
}

// project_packages walks, selects and parses the packages a command works on.
project_packages :: proc(p: ^Project, paths: []string) -> []Package {
	rels := package_dirs(p.root, &p.cfg)
	if len(paths) > 0 {
		rels = select_packages(p.root, rels, paths)
		if len(rels) == 0 {fail("no packages under %v", paths)}
	}
	pkgs := load_packages(p.root, &p.cfg, rels)
	for pk in pkgs {
		if pk.role_count > 1 {fail("%s matches more than one role in %s", pk.rel, CONFIG_FILE)}
	}
	return pkgs
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
	c := Ctx {
		root = p.root,
		cfg  = &p.cfg,
		rb   = &p.rb,
		r    = new(Report),
	}
	c.pkgs = project_packages(&p, nil)
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
	fmt.printfln(
		"%d ignores, %d bad. Not ignorable: odin/*, odx/*, layering/R1",
		len(igs),
		len(c.r.violations),
	)
}
