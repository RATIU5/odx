package odx

import "core:os"
import "core:strings"

// Git paths include deleted files; rename endpoints are separate paths. NUL delimiters
// preserve filenames that Git would otherwise quote or split across lines.
git_changed :: proc(root, ref: string) -> (files: []string, ok: bool) {
	paths := make(map[string]bool)
	for args in ([][]string{{"git", "-C", root, "diff", "--relative", "--no-renames", "--name-only", "-z", ref, "--", "."}, {"git", "-C", root, "ls-files", "--others", "--exclude-standard", "-z", "--", "."}}) {
		state, stdout, _, err := os.process_exec({command = args}, context.allocator)
		if err != nil || state.exit_code != 0 {return nil, false}
		for path in strings.split(string(stdout), "\x00", context.temp_allocator) {
			if path != "" {paths[path] = true}
		}
	}
	return sorted_keys(paths), true
}

check_input :: proc(path: string) -> bool {
	if strings.has_suffix(path, ".odin") {return true}
	if path == CONFIG_FILE || path == BASELINE_FILE || path == PROJECT_TOPICS_DIR {return true}
	return strings.has_prefix(path, PROJECT_TOPICS_DIR + "/")
}

// Changed inputs trigger current-project reporting, including unchanged importers.
changed_check_inputs :: proc(root, ref: string) -> (files: []string, ok: bool) {
	rels, changed_ok := git_changed(root, ref)
	if !changed_ok {return nil, false}
	out := make([dynamic]string)
	for rel in rels {if check_input(rel) {append(&out, rel)}}
	return out[:], true
}
