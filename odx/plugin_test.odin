package odx

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_plugins :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator // ponytail: the CLI never frees; the leak checker would
	defer free_all(context.temp_allocator)
	root, _ := os.make_directory_temp("", "odx-plugin-test-*", context.allocator)
	defer os.remove_all(root)
	os.make_directory_all(join({root, ".odx", "plugins"}))
	exe := join({root, ".odx", "plugins", "odx-demo"})
	script := `#!/bin/sh
[ "$1" = "--describe" ] && { echo '{"protocol":1,"checks":["demo/R1"]}'; exit 0; }
cat >/dev/null
echo '{"violations":[{"file":"a.odin","line":3,"col":0,"message":"nope"}]}'
`
	_ = os.write_entire_file(exe, transmute([]byte)script)
	_ = os.chmod(exe, os.Permissions_Read_Write_All + os.Permissions_Execute_All)
	cfg: Config
	cfg.plugins["demo"] = sha256_hex(transmute([]byte)script)
	cfg.plugins["ghost"] = "00"
	r: Report
	c := Ctx{root = root, cfg = &cfg, r = &r}
	run_plugins(&c)
	testing.expect_value(t, len(r.violations), 1)
	if len(r.violations) == 1 {
		v := r.violations[0]
		testing.expect(t, v.rule == "demo/R1" && v.file == "a.odin" && v.line == 3 && v.col == 1 && v.check == "plugin:demo", v.message)
	}
	testing.expect_value(t, len(r.tool_errors), 1) // ghost: not found
	// hash mismatch and bad protocol are tool errors, never passes
	delete_key(&cfg.plugins, "ghost")
	cfg.plugins["demo"] = "deadbeef"
	r = {}
	run_plugins(&c)
	testing.expect(t, len(r.tool_errors) == 1 && strings.contains(r.tool_errors[0], "sha256 mismatch"))
}
