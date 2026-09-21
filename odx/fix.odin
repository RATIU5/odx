package odx

import "core:fmt"
import "core:os"
import "core:strings"

// `odx fix` (20.1): the textual, unambiguous subset. Today that is one thing: deleting stale
// ignore directives (odx/stale-ignore). Refuses on a dirty worktree unless --allow-dirty and
// always outside git, because `git checkout` is the undo.

cmd_fix :: proc(o: Opts) {
	p := must_load(o, true)
	if !o.dry_run {
		state, out, _, err := os.process_exec(
			{command = {"git", "status", "--porcelain"}, working_dir = p.root},
			context.allocator,
		)
		if err != nil ||
		   state.exit_code != 0 {fail("fix needs a git worktree (the undo is git checkout)")}
		if len(strings.trim_space(string(out))) > 0 &&
		   !o.allow_dirty {fail("worktree is dirty; commit first or pass --allow-dirty")}
	}
	c := make_ctx(&p, o.args[:])
	if run_checks(&c, Opts{args = o.args}) == EXIT_TOOL {
		print_tool_errors(c.r)
		fail("checks did not run to completion; fixing nothing")
	}
	fixed := apply_fixes(p.root, c.r, o.dry_run)
	remaining := len(c.r.violations) - fixed
	fmt.printfln(
		"%s %d stale ignores, %d violations remain",
		"would remove" if o.dry_run else "removed",
		fixed,
		remaining,
	)
	if remaining > 0 {os.exit(EXIT_VIOLATION)}
}

// apply_fixes deletes every odx/stale-ignore directive in the report; returns how many.
// The report is sorted by file then line, so one file's directives are contiguous.
apply_fixes :: proc(root: string, r: ^Report, dry_run: bool) -> (n: int) {
	vs := r.violations[:]
	for i := 0; i < len(vs); i += 1 {
		if vs[i].rule != "odx/stale-ignore" {continue}
		file := vs[i].file
		j := i
		for j < len(vs) && vs[j].file == file && vs[j].rule == "odx/stale-ignore" {j += 1}
		n += len(vs[i:j])
		strip_lines(join({root, file}), file, vs[i:j], dry_run)
		i = j - 1
	}
	return
}

// strip_lines removes the directive at (line, col) for each violation; a directive alone on its
// line takes the line with it.
@(private = "file")
strip_lines :: proc(path, rel: string, vs: []Violation, dry_run: bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {fail("%s: cannot read", path)}
	src := strings.split_lines(string(data), context.temp_allocator)
	keep := make([dynamic]string, context.temp_allocator)
	for l, i in src {
		v: ^Violation
		for &cand in vs {if cand.line == i + 1 {v = &cand}}
		if v == nil {
			append(&keep, l)
			continue
		}
		at := v.col - 1
		if dry_run {fmt.printfln("%s:%d: remove `%s`", rel, v.line, strings.trim_space(l[at:]))}
		if code := strings.trim_right_space(l[:at]); code != "" {append(&keep, code)}
	}
	eol := "\r\n" if strings.contains(string(data), "\r\n") else "\n"
	if !dry_run {write_atomic(path, strings.join(keep[:], eol))}
}
