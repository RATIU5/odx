package odx

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:testing"

GOLDEN :: #directory + "/../tests/golden"

// Each case dir holds an `expected` file: the command, exit code, stdout and stderr.
@(test)
test_golden :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases, err := os.read_all_directory_by_path(GOLDEN, context.allocator)
	testing.expect_value(t, err, nil)
	testing.expect(t, len(cases) > 0, "no golden cases")
	slice.sort_by(cases, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for c in cases {
		if c.type != .Directory {continue}
		path, _ := filepath.join({c.fullpath, "expected"})
		data, read_err := os.read_entire_file(path, context.allocator)
		if !testing.expectf(t, read_err == nil, "%s: %v", c.name, read_err) {continue}
		expected := string(data)
		command, _, _ := strings.partition(expected, "\n")
		args, _ := strings.fields(strings.trim_prefix(command, "$ odx"))

		out, stderr: strings.Builder
		code := run(args, c.fullpath, &out, &stderr)
		actual := fmt.aprintf(
			"%s\nexit %d\nstdout:\n%sstderr:\n%s",
			command,
			code,
			strings.to_string(out),
			strings.to_string(stderr),
		)
		testing.expectf(
			t,
			actual == expected,
			"%s\n--- expected\n%s--- actual\n%s",
			c.name,
			expected,
			actual,
		)
	}
}

@(test)
test_sort_and_dedup :: proc(t: ^testing.T) {
	r: Report
	defer delete(r.findings)
	append(
		&r.findings,
		Finding{"b.odin", 1, "x", "m"},
		Finding{"a.odin", 10, "x", "m"},
		Finding{"a.odin", 9, "y", "m"},
		Finding{"a.odin", 9, "x", "m"},
		Finding{"a.odin", 9, "x", "m"},
		Finding{"a", 0, "package-role", "m"},
	)
	finish(&r)
	testing.expect_value(t, len(r.findings), 5)
	testing.expect_value(t, r.findings[0], Finding{"a", 0, "package-role", "m"})
	testing.expect_value(t, r.findings[1], Finding{"a.odin", 9, "x", "m"})
	testing.expect_value(t, r.findings[2], Finding{"a.odin", 9, "y", "m"})
	testing.expect_value(t, r.findings[3], Finding{"a.odin", 10, "x", "m"})
	testing.expect_value(t, r.findings[4], Finding{"b.odin", 1, "x", "m"})
}

@(test)
test_exit_code :: proc(t: ^testing.T) {
	r: Report
	defer delete(r.findings)
	defer delete(r.errors)
	testing.expect_value(t, exit_code(r), 0)
	append(&r.findings, Finding{"a.odin", 1, "x", "m"})
	testing.expect_value(t, exit_code(r), 1)
	append(&r.errors, "couldn't")
	testing.expect_value(t, exit_code(r), 2)
}

@(test)
test_output :: proc(t: ^testing.T) {
	r: Report
	defer delete(r.findings)
	defer delete(r.errors)
	append(
		&r.findings,
		Finding{"a", 0, "package-role", "m"},
		Finding{"a/a.odin", 3, "mutable-state", "say \"hi\""},
	)
	append(&r.errors, "e")

	out, err, js: strings.Builder
	defer strings.builder_destroy(&out)
	defer strings.builder_destroy(&err)
	defer strings.builder_destroy(&js)
	write_text(r, &out, &err)
	testing.expect_value(
		t,
		strings.to_string(out),
		"a: package-role: m\na/a.odin:3: mutable-state: say \"hi\"\n",
	)
	testing.expect_value(t, strings.to_string(err), "odx: e\nfindings: 2  ignores: 0\n")
	write_json(r, &js)
	testing.expect_value(
		t,
		strings.to_string(js),
		`{"findings":[{"file":"a","line":0,"rule":"package-role","message":"m"},{"file":"a/a.odin","line":3,"rule":"mutable-state","message":"say \"hi\""}],"errors":["e"],"ignores":0}` +
		"\n",
	)
}

@(test)
test_config_decode :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	decode :: proc(s: string) -> (Config, string) {
		entries, reason := read_object(s)
		if reason != "" {return {}, reason}
		return decode_config(entries)
	}
	cfg, reason := decode(`{}`)
	testing.expect_value(t, len(cfg.compiler_flags), len(DEFAULT_COMPILER_FLAGS))
	cfg, reason = decode(`{"compiler_flags": [], "edge": ["app"]}`)
	testing.expect_value(t, reason, "")
	testing.expect_value(t, len(cfg.compiler_flags), 0)
	testing.expect_value(t, cfg.roles[.edge][0], "app")
	// Syntax is checked before the schema.
	_, reason = decode(`{"exlcude": [], `)
	testing.expect_value(t, reason, "not valid JSON")
	_, reason = decode(`[ broken`)
	testing.expect_value(t, reason, "not valid JSON")
	_, reason = decode(`{"pure": [1]}`)
	testing.expect_value(t, reason, `"pure" element 0 is a number, not a string`)
}
