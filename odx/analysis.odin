package odx

Analysis_Options :: struct {
	root:           string,
	paths:          []string,
	topics:         []string,
	since:          string,
	fast:           bool,
	strict:         bool,
	max_violations: int,
}

analyze :: proc(o: Analysis_Options) -> (r: ^Report, code: int) {
	p := load_project(o.root)
	r = new(Report)
	if p.root == "" {errf(&p.errs, "no %s found here or in any parent (use --root)", CONFIG_FILE)}
	for topic in o.topics {
		if find_topic(&p.rb, topic) == nil {errf(&p.errs, "unknown topic %q", topic)}
	}
	if len(p.errs) > 0 {
		r.tool_errors = p.errs
		return r, finalize(r, &p.rb, o.strict, o.max_violations)
	}
	paths := o.paths
	selection := Selection.paths
	selection_reason := ""
	if o.since != "" {
		changed, ok := changed_check_inputs(p.root, o.since)
		if !ok {
			tool_error(
				r,
				"--since could not read changes; check the git worktree and reference %q",
				o.since,
			)
			return r, finalize(r, &p.rb, o.strict, o.max_violations)
		}
		paths = nil
		if len(changed) == 0 {
			selection = .nothing
			selection_reason = "no changed project source or policy inputs; no packages checked"
		} else {
			selection_reason = "changed source or policy inputs trigger full current-project reporting, including unchanged dependents"
		}
	}
	c := make_ctx(&p, paths, o.topics, selection)
	if selection_reason != "" {c.selection_reason = selection_reason}
	code = run_checks(&c, o)
	return c.r, code
}

run_checks :: proc(c: ^Ctx, o: Analysis_Options, use_baseline := true) -> int {
	if len(c.r.tool_errors) > 0 {return finalize(c.r, c.rb, o.strict, o.max_violations)}
	full := !o.fast && len(o.topics) == 0 && len(o.paths) == 0 && o.since == ""
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
	if use_baseline {apply_baseline(c, full && c.r.coverage.complete)}
	refresh_coverage(c.r)
	return finalize(c.r, c.rb, o.strict, o.max_violations)
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
