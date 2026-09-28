package odx

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:testing"

TESTS :: #directory + "/../tests"

// Golden cases live in tests/golden-NN/<behavior>/, one test proc per part. Each case dir is
// a repository root holding its inputs and an `expected` file: the `$ odx ...` command, the
// exit code, stdout and stderr.
@(test)
test_golden_01 :: proc(t: ^testing.T) {
	run_golden(t, "golden-01")
}

@(test)
test_golden_02 :: proc(t: ^testing.T) {
	run_golden(t, "golden-02")
}

run_golden :: proc(t: ^testing.T, part: string) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Real and absolute, as main passes the root, and short in failure labels.
	tests, err := os.get_absolute_path(TESTS, context.allocator)
	testing.expect_value(t, err, nil)
	dir, _ := filepath.join({tests, part})
	cases, read_err := os.read_all_directory_by_path(dir, context.allocator)
	testing.expect_value(t, read_err, nil)
	slice.sort_by(cases, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	n := 0
	for c in cases {
		name := fmt.aprintf("%s/%s", part, c.name)
		if !testing.expectf(t, c.type == .Directory, "%s: not a case directory", name) {continue}
		n += 1
		path, _ := filepath.join({c.fullpath, "expected"})
		data, data_err := os.read_entire_file(path, context.allocator)
		if !testing.expectf(t, data_err == nil, "%s: expected: %v", name, data_err) {continue}
		expected := string(data)
		command, _, _ := strings.partition(expected, "\n")
		if !testing.expectf(
			t,
			command == "$ odx" || strings.has_prefix(command, "$ odx "),
			"%s: first line %q is not `$ odx ...`",
			name,
			command,
		) {continue}
		args, _ := strings.fields(strings.trim_prefix(command, "$ odx"))

		out, stderr: strings.Builder
		code := run(args, c.fullpath, strings.to_writer(&out), strings.to_writer(&stderr))
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
			name,
			expected,
			actual,
		)
	}
	testing.expectf(t, n > 0, "%s: no golden cases", part)
}

@(test)
test_sort_and_dedup :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	r: Report
	append(
		&r.findings,
		Finding{"b.odin", 1, 1, .compiler, "m"},
		Finding{"a.odin", 10, 1, .compiler, "m"},
		Finding{"a.odin", 9, 2, .compiler, "m"},
		Finding{"a.odin", 9, 1, .mutable_state, "m"},
		Finding{"a.odin", 9, 1, .leak, "m"},
		Finding{"a.odin", 9, 1, .leak, "two\n  lines"},
		Finding{"a.odin", 9, 1, .leak, "two lines"},
		Finding{"a", 0, 0, .package_role, "m"},
	)
	append(
		&r.reasons,
		Reason{"odx.json", 2, 1, "b"},
		Reason{"", 0, 0, "z"},
		Reason{"odx.json", 1, 5, "a"},
		Reason{"odx.json", 0, 0, "c"},
		Reason{"odx.json", 1, 5, "a"},
	)
	finish(&r)
	// Rules sort by published name ("leak" < "mutable-state"), not enum order.
	testing.expect(
		t,
		slice.equal(
			r.findings[:],
			[]Finding {
				{"a", 0, 0, .package_role, "m"},
				{"a.odin", 9, 1, .leak, "m"},
				{"a.odin", 9, 1, .leak, "two lines"},
				{"a.odin", 9, 1, .mutable_state, "m"},
				{"a.odin", 9, 2, .compiler, "m"},
				{"a.odin", 10, 1, .compiler, "m"},
				{"b.odin", 1, 1, .compiler, "m"},
			},
		),
	)
	testing.expect(
		t,
		slice.equal(
			r.reasons[:],
			[]Reason {
				{"", 0, 0, "z"},
				{"odx.json", 0, 0, "c"},
				{"odx.json", 1, 5, "a"},
				{"odx.json", 2, 1, "b"},
			},
		),
	)
}

@(test)
test_one_line :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	testing.expect_value(t, one_line("a  b"), "a  b")
	testing.expect_value(t, one_line("a\n\tb\r\n\n c \r"), "a b c")
	testing.expect_value(t, one_line("a\rb"), "a b")
}

@(test)
test_exit_code :: proc(t: ^testing.T) {
	r: Report
	defer delete(r.findings)
	defer delete(r.reasons)
	testing.expect_value(t, exit_code(r), 0)
	append(&r.findings, Finding{"a.odin", 1, 1, .compiler, "m"})
	testing.expect_value(t, exit_code(r), 1)
	append(&r.reasons, Reason{message = "couldn't"})
	testing.expect_value(t, exit_code(r), 2)
}

@(test)
test_rule_names :: proc(t: ^testing.T) {
	seen: map[string]bool
	defer delete(seen)
	for name, rule in RULE_NAMES {
		testing.expectf(t, name != "" && name != "all", "%v: bad name %q", rule, name)
		testing.expectf(t, !(name in seen), "%v: repeated name %q", rule, name)
		seen[name] = true
	}
}

@(test)
test_output :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	r: Report
	append(
		&r.findings,
		Finding{"a", 0, 0, .package_role, "m"},
		Finding{"a/a.odin", 3, 7, .mutable_state, "say \"hi\""},
	)
	append(
		&r.reasons,
		Reason{"", 0, 0, "e"},
		Reason{"odx.json", 0, 0, "f"},
		Reason{"odx.json", 2, 3, "g"},
	)
	r.ignores = 4

	out, err, js: strings.Builder
	testing.expect_value(t, write_text(r, strings.to_writer(&out), strings.to_writer(&err)), nil)
	testing.expect_value(
		t,
		strings.to_string(out),
		"a: package-role: m\na/a.odin:3:7: mutable-state: say \"hi\"\n",
	)
	testing.expect_value(
		t,
		strings.to_string(err),
		"odx: e\nodx: odx.json: f\nodx: odx.json:2:3: g\nfindings: 2  ignores: 4\n",
	)
	testing.expect_value(t, write_json(r, strings.to_writer(&js)), nil)
	testing.expect_value(
		t,
		strings.to_string(js),
		`{"version":1,"findings":[{"path":"a","line":0,"column":0,"rule":"package-role","message":"m"},` +
		`{"path":"a/a.odin","line":3,"column":7,"rule":"mutable-state","message":"say \"hi\""}],` +
		`"errors":[{"path":"","line":0,"column":0,"message":"e"},` +
		`{"path":"odx.json","line":0,"column":0,"message":"f"},` +
		`{"path":"odx.json","line":2,"column":3,"message":"g"}],"ignores":4}` +
		"\n",
	)
}

// decode_string runs odx.json decoding on s and returns its reasons as text lines.
decode_string :: proc(s: string) -> (cfg: Config, lines: string) {
	r: Report
	d := Decoder {
		r    = &r,
		data = s,
	}
	if root, ok := parse_json(&d); ok {
		cfg = decode_config(&d, root)
	}
	finish(&r)
	b: strings.Builder
	for e in r.reasons {
		fmt.sbprintf(&b, "%d:%d: %s\n", e.line, e.column, e.message)
	}
	return cfg, strings.to_string(b)
}

@(test)
test_config_decode :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cfg, lines := decode_string(
		`{"version": 1, "packages": {"app": ["app", "."], "external": ["x"]},` +
		"\n" +
		`"collections": ["lib=libs"], "defines": ["X=1"], "exclude_dirs": []}`,
	)
	testing.expect_value(t, lines, "")
	testing.expect_value(t, cfg.version, 1)
	testing.expect_value(t, cfg.packages[.app][1], Entry{".", 1, 44})
	testing.expect_value(t, cfg.packages[.external][0].value, "x")
	testing.expect_value(t, cfg.collections[0], Entry{"lib=libs", 2, 17})
	testing.expect_value(t, cfg.defines[0].value, "X=1")

	cases := [][2]string {
		// Syntax: one error, at the first problem, before any key is checked.
		{`{"exlcude": [], `, "1:17: not valid JSON: unexpected end of file\n"},
		{``, "1:1: not valid JSON: unexpected end of file\n"},
		{`{"version": 1, "defines": ["a",]}`, "1:31: not valid JSON: trailing comma\n"},
		{`{"version": 1 /* c */}`, "1:15: not valid JSON: comment\n"},
		{"{\"version\": 1}\x00", "1:15: not valid JSON\n"},
		{`{'version': 1}`, "1:2: not valid JSON\n"},
		{`{"version": 01}`, "1:13: not valid JSON\n"},
		{`{"version": +1}`, "1:13: not valid JSON\n"},
		{`{"version": NaN}`, "1:13: not valid JSON\n"},
		{`{"version": 1, "defines": ["a` + "\t" + `"]}`, "1:28: not valid JSON\n"},
		{`{"version": 1, "defines": ["\x"]}`, "1:28: not valid JSON\n"},
		{"{\"version\": 1, \"defines\": [\"\xff\"]}", "1:28: not valid JSON\n"},
		{`{version: 1}`, "1:2: not valid JSON\n"},
		// Columns count code points.
		{`{"é": 1,}`, "1:8: not valid JSON: trailing comma\n"},
		// Version.
		{
			`{"version": 1e0}`,
			`1:13: "version" is 1e0, not an integer; supported versions: 1` + "\n",
		},
		{
			`{"version": null}`,
			`1:13: "version" is null, not an integer; supported versions: 1` + "\n",
		},
		{
			`{"version": 99999999999999999999}`,
			"1:13: version 99999999999999999999 is not supported; supported versions: 1\n",
		},
		{`{"version": 0, "x": 1}`, "1:13: version 0 is not supported; supported versions: 1\n"},
		// Shape, at any level.
		{`{"version": 1, "packages": {"app": [], "app": []}}`, `1:40: repeated key "app"` + "\n"},
		{
			`{"version": 1, "defines": [{"a": 1, "a": 2}]}`,
			"1:28: element of \"defines\" is an object, not a string\n1:37: repeated key \"a\"\n",
		},
		{`{"version": 1, "compiler_flags": []}`, `1:16: unknown key "compiler_flags"` + "\n"},
		{
			`{"version": 1, "packages": {"external": [true]}}`,
			`1:42: element of "packages.external" is true, not a string` + "\n",
		},
		{
			`{"version": 1, "collections": {}}`,
			`1:31: "collections" is an object, not an array of strings` + "\n",
		},
		{`"x"`, "1:1: top-level value is a string, not an object\n"},
	}
	for c in cases {
		_, got := decode_string(c[0])
		testing.expectf(t, got == c[1], "%q:\n--- expected\n%s--- actual\n%s", c[0], c[1], got)
	}
}
