package odx

import "core:os"
import "core:strings"
import "core:testing"

// The generated odx.json5 must load through the real loader, and a tool error from
// `odx check --json` must never read as "clean".
@(test)
test_eval_config_loads :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	dir := strings.concatenate({os.get_env("TMPDIR", context.temp_allocator), "/odx-eval-cfg"})
	os.remove_all(dir)
	os.make_directory_all(strings.concatenate({dir, "/", EVAL_PACKAGE}))
	defer os.remove_all(dir)
	testing.expect_value(
		t,
		os.write_entire_file(
			strings.concatenate({dir, "/", EVAL_PACKAGE, "/task.odin"}),
			transmute([]byte)string("package task\n"),
		),
		nil,
	)
	testing.expect_value(
		t,
		os.write_entire_file(
			strings.concatenate({dir, "/", CONFIG_FILE}),
			transmute([]byte)string(EVAL_CONFIG),
		),
		nil,
	)
	p := load_project(dir)
	testing.expect_value(t, len(p.errs), 0)
	for e in p.errs {testing.expectf(t, false, "config error: %s", e)}
	testing.expect_value(t, len(p.cfg.roles["pure"]), 1)
}

@(test)
test_parse_check_json :: proc(t: ^testing.T) {
	_, ok := parse_check_json(transmute([]byte)string("odx: odx.json5: Invalid_Data\n"))
	testing.expect(t, !ok, "an error line must not score as zero violations")
	n, ok2 := parse_check_json(
		transmute([]byte)string(
			`{"schema":1,"violations":[],"summary":{"errors":2,"warnings":1}}`,
		),
	)
	testing.expect(t, ok2)
	testing.expect_value(t, n, 3)
}

// Headless `claude -p` ends the session on a PostToolBatch block, so the loop condition wires
// only the Stop hook (which does feed back and continue).
@(test)
test_eval_hooks_stop_only :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	s := eval_hooks("/x/odx")
	testing.expect(t, strings.contains(s, `"/x/odx hook stop"`))
	testing.expect(t, !strings.contains(s, "hook edit"))
	testing.expect(t, !strings.contains(s, "PostToolBatch"))
}
