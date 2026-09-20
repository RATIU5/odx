package odx

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// `odx fix` (20.1): the textual, unambiguous subset. Today that is one thing: deleting stale
// stale ignore directives (odx/stale-ignore). Refuses on a dirty worktree unless --allow-dirty and
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
	r, _ := run_checks(&p, Opts{args = o.args})
	fixed := apply_fixes(p.root, r, o.dry_run)
	remaining := len(r.violations) - fixed
	fmt.printfln(
		"%s %d stale ignores, %d violations remain",
		"would remove" if o.dry_run else "removed",
		fixed,
		remaining,
	)
	if remaining > 0 {os.exit(EXIT_VIOLATION)}
}

// apply_fixes deletes every odx/stale-ignore directive in the report; returns how many.
apply_fixes :: proc(root: string, r: ^Report, dry_run: bool) -> (n: int) {
	by_file := make(map[string][dynamic]int, context.temp_allocator)
	for v in r.violations {
		if v.rule != "odx/stale-ignore" {continue}
		lines := by_file[v.file] // &map[k] is nil for a missing key; copy, append, store back
		append(&lines, v.line)
		by_file[v.file] = lines
	}
	for file in sorted_keys(by_file) {
		lines := by_file[file]
		path := join({root, file})
		data, err := os.read_entire_file(path, context.allocator)
		if err != nil {fail("%s: cannot read", path)}
		src := strings.split_lines(string(data), context.temp_allocator)
		keep := make([dynamic]string, context.temp_allocator)
		for l, i in src {
			if !slice.contains(lines[:], i + 1) {
				append(&keep, l)
				continue
			}
			n += 1
			at := strings.index(l, "// " + IGNORE_PREFIX)
			if dry_run {fmt.printfln("%s:%d: remove `%s`", file, i + 1, strings.trim_space(l[at:]))}
			if code := strings.trim_right_space(l[:at]); code != "" {append(&keep, code)}
		}
		if !dry_run {write_atomic(path, strings.join(keep[:], "\n"))}
	}
	return
}
