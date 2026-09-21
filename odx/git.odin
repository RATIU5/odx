package odx

import "core:os"
import "core:strings"

// git_changed: files changed since ref plus untracked ones, root-relative; ok is false outside
// a git worktree (callers then fall back to a full scan).
git_changed :: proc(root, ref: string) -> (files: []string, ok: bool) {
	out := make([dynamic]string)
	for args in ([][]string{{"git", "-C", root, "diff", "--name-only", ref, "--"}, {"git", "-C", root, "ls-files", "--others", "--exclude-standard"}}) {
		state, stdout, _, err := os.process_exec({command = args}, context.allocator)
		if err != nil || state.exit_code != 0 {return nil, false}
		for l in strings.split_lines(string(stdout), context.temp_allocator) {if l != "" {append(&out, l)}}
	}
	return out[:], true
}

// changed_odin_files: absolute paths of the changed .odin files, for make_ctx's package
// selection. in_git is false outside a worktree; callers then scan everything.
changed_odin_files :: proc(root, ref: string) -> (files: []string, in_git: bool) {
	rels, ok := git_changed(root, ref)
	if !ok {return nil, false}
	out := make([dynamic]string)
	for r in rels {if strings.has_suffix(r, ".odin") && os.exists(join({root, r})) {append(&out, join({root, r}))}}
	return out[:], true
}

// added_ignores: the suppressions whose directive text is not in HEAD's copy of the file (M3.3).
added_ignores :: proc(root: string, igs: []Ignore) -> []Ignore {
	out := make([dynamic]Ignore)
	if st, _, _, err := os.process_exec(
		{command = {"git", "-C", root, "rev-parse", "--verify", "HEAD"}},
		context.allocator,
	); err != nil || st.exit_code != 0 {return nil} 	// no HEAD: nothing to be "since"
	heads := make(map[string]string, context.temp_allocator)
	for ig in igs {
		old, cached := heads[ig.file]
		if !cached {
			_, stdout, _, err := os.process_exec(
				{
					command = {
						"git",
						"-C",
						root,
						"show",
						strings.concatenate({"HEAD:", ig.file}, context.temp_allocator),
					},
				},
				context.allocator,
			)
			old = string(stdout) if err == nil else ""
			heads[ig.file] = old
		}
		tail := strings.concatenate({" ", ig.rule, " reason: ", ig.reason}, context.temp_allocator)
		if !strings.contains(
			   old,
			   strings.concatenate({IGNORE_PREFIX, tail}, context.temp_allocator),
		   ) &&
		   !strings.contains(
				   old,
				   strings.concatenate({IGNORE_FILE_PREFIX, tail}, context.temp_allocator),
			   ) {
			append(&out, ig)
		}
	}
	return out[:]
}
