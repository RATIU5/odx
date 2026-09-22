package milestone_probe

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

main :: proc() {
	bin := os.get_env("ODX", context.allocator)
	if bin == "" {
		cwd, _ := os.get_working_directory(context.allocator)
		bin = filepath.join({cwd, "build/odx"}, context.allocator) or_else ""
	}
	root, err := os.make_directory_temp("", "odx-cleanup-*", context.allocator)
	if err != nil {panic("cannot create scratch project")}
	defer os.remove_all(root)
	ignore := strings.concatenate({root, "/.gitignore"})
	original := "build/\n# Project-owned exceptions\n!build/keep.txt\n"
	if os.write_entire_file(ignore, original) != nil {panic("cannot write scratch ignore file")}
	cmd := []string{bin, "init", "--root", root}
	state, out, errors, run_err := os.process_exec({command = cmd}, context.allocator)
	if run_err != nil || state.exit_code != 0 {
		fmt.eprintfln("init failed: %v\n%s\n%s", run_err, out, errors)
		os.exit(1)
	}
	data, read_err := os.read_entire_file(ignore, context.allocator)
	if read_err != nil || string(data) != original {panic("init changed existing .gitignore")}
	for name in ([]string{"odx.json5", "mise.toml"}) {
		if !os.exists(strings.concatenate({root, "/", name})) {panic("init omitted configuration")}
	}
	if os.exists(strings.concatenate({root, "/.odx/cache"})) {panic("init created unused cache")}
	fmt.println("PASS init preserves .gitignore and writes configuration without cache setup")
}
