package odx

import "core:os"
import "core:strings"

// Files changed since ref plus untracked ones, root-relative; ok is false outside a git
// worktree (callers then fall back to a full scan).
git_changed :: proc(root, ref: string) -> (files: []string, ok: bool) {
	out := make([dynamic]string)
	for args in ([][]string{{"git", "-C", root, "diff", "--name-only", ref, "--"}, {"git", "-C", root, "ls-files", "--others", "--exclude-standard"}}) {
		state, stdout, _, err := os.process_exec({command = args}, context.allocator)
		if err != nil || state.exit_code != 0 {return nil, false}
		for l in strings.split_lines(string(stdout), context.temp_allocator) {if l != "" {append(&out, l)}}
	}
	return out[:], true
}

// Absolute paths; in_git is false outside a worktree, and callers then scan everything.
changed_odin_files :: proc(root, ref: string) -> (files: []string, in_git: bool) {
	rels, ok := git_changed(root, ref)
	if !ok {return nil, false}
	out := make([dynamic]string)
	for r in rels {if strings.has_suffix(r, ".odin") && os.exists(join({root, r})) {append(&out, join({root, r}))}}
	return out[:], true
}
