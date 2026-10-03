package odx

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:testing"

PIN :: "dev-2026-09-nightly:a2fb372"

@(test)
parse_config_rejects_json_that_is_not_strict :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	cases := []struct {
		text, message: string,
	} {
		{`{"version": 1,}`, "odx.json:1:14: not strict JSON: trailing comma"},
		{`{"vendored": ["a",]}`, "odx.json:1:18: not strict JSON: trailing comma"},
		{"{\"version\": 1}\x00junk", "odx.json:1:15: not strict JSON: unexpected NUL byte"},
		{"{\"version\": 1}\v", "odx.json:1:15: not strict JSON: unexpected character"},
		{"{\"version\": 1} // c", "odx.json:1:16: not strict JSON: unexpected character"},
		{`{'version': 1}`, "odx.json:1:2: not strict JSON: unexpected character"},
		{`{"version": 01}`, "odx.json:1:13: not strict JSON: invalid number"},
		{
			`{"version": 1} {}`,
			"odx.json:1:16: not strict JSON: unexpected text after the JSON value",
		},
		{`{"odin": "a\x"}`, "odx.json:1:10: not strict JSON: invalid string"},
		{"{\"odin\": \"a\tb\"}", "odx.json:1:10: not strict JSON: invalid string"},
		{
			`{"version": 1, "version": 1}`,
			"odx.json:1:16: not strict JSON: duplicate key 'version'",
		},
		{`{"version": 1`, "odx.json:1:14: not strict JSON: unexpected end of file"},
		{"", "odx.json:1:1: not strict JSON: unexpected end of file"},
		{`{version: 1}`, "odx.json:1:2: not strict JSON: expected a quoted key"},
		{`{"version" 1}`, "odx.json:1:12: not strict JSON: expected ':'"},
		{`{"version": 1 "odin": ""}`, "odx.json:1:15: not strict JSON: expected ',' or '}'"},
		{
			"{\n  \"é\": 1,\n  \"version\": NaN}",
			"odx.json:3:14: not strict JSON: expected a value",
		},
	}
	for c in cases {
		_, errors := parse_config(c.text, ".", allocator)
		testing.expectf(
			t,
			len(errors) == 1,
			"%q: got %d errors, want 1: %v",
			c.text,
			len(errors),
			errors,
		)
		if len(errors) == 1 {
			testing.expect_value(t, errors[0].code, Error_Code.Config_Invalid)
			testing.expectf(
				t,
				errors[0].message == c.message,
				"%q: got %q, want %q",
				c.text,
				errors[0].message,
				c.message,
			)
		}
	}
}

@(test)
parse_config_keeps_pending_keys_in_order_with_positions :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	text := fmt.tprintf(
		"{{\n  \"version\": 1,\n  \"odin\": \"%s\",\n  \"pending\": {{\"zeta\": \"r1\",\n\t\"é/b\": \"r2\", \"a\": \"r3\"}}\n}}\n",
		PIN,
	)
	config, errors := parse_config(text, ".", allocator)
	testing.expectf(t, len(errors) == 0, "unexpected errors: %v", errors)
	want := []Pending_Entry {
		{dir = "zeta", reason = "r1", line = 4, col = 15},
		{dir = "é/b", reason = "r2", line = 5, col = 2},
		{dir = "a", reason = "r3", line = 5, col = 15},
	}
	testing.expect_value(t, len(config.pending), len(want))
	for w, i in want {
		if i < len(config.pending) {
			testing.expect_value(t, config.pending[i], w)
		}
	}
	testing.expect_value(t, config.rule_set, 1)
	testing.expect_value(t, config.odin, PIN)
}

@(test)
parse_config_reports_every_schema_problem_in_source_order :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	text := `{"odin": 7, "bogus": [], "version": 0, "pending": {"lib": "  "}, "vendored": ["lib/"]}`
	_, errors := parse_config(text, ".", allocator)
	want := []string {
		"'odin' must be a string",
		"unknown key 'bogus'",
		"'version' 0 is not a rule set",
		"'pending' entry 'lib' has an empty reason",
		"'lib/' is listed under both 'vendored' and 'pending'",
	}
	testing.expect_value(t, len(errors), len(want))
	for w, i in want {
		if i < len(errors) {
			testing.expect_value(t, errors[i].message, w)
		}
	}
}

@(test)
parse_config_rejects_a_collection_symlinked_outside_the_repo :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	tmp, tmp_err := os.make_directory_temp("", "odx-config-*", allocator)
	testing.expect_value(t, tmp_err, nil)
	defer os.remove_all(tmp)
	root := fmt.aprintf("%s/repo", tmp, allocator = allocator)
	testing.expect_value(
		t,
		os.make_directory_all(fmt.aprintf("%s/inside", root, allocator = allocator)),
		nil,
	)
	testing.expect_value(
		t,
		os.make_directory(fmt.aprintf("%s/outside", tmp, allocator = allocator)),
		nil,
	)
	testing.expect_value(
		t,
		os.symlink("../outside", fmt.aprintf("%s/out", root, allocator = allocator)),
		nil,
	)
	testing.expect_value(
		t,
		os.symlink("inside", fmt.aprintf("%s/in", root, allocator = allocator)),
		nil,
	)

	text := fmt.aprintf(
		`{{"version": 1, "odin": "%s", "collections": ["a=out", "b=in", "c=%s/inside"]}}`,
		PIN,
		root,
		allocator = allocator,
	)
	config, errors := parse_config(text, root, allocator)
	testing.expect_value(t, len(errors), 1)
	if len(errors) == 1 {
		testing.expect_value(t, errors[0].message, "collection 'a' path 'out' is outside the repo")
	}
	real_root, _ := os.get_absolute_path(root, allocator)
	want := fmt.aprintf("%s/inside", real_root, allocator = allocator)
	testing.expect_value(t, len(config.collections), 2)
	if len(config.collections) == 2 {
		testing.expect_value(t, config.collections[0], Collection{"b", want})
		testing.expect_value(t, config.collections[1], Collection{"c", want})
	}
}

@(test)
find_repo_prefers_the_nearest_odx_json_then_git_then_cwd :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	tmp_raw, tmp_err := os.make_directory_temp("", "odx-root-*", allocator)
	testing.expect_value(t, tmp_err, nil)
	defer os.remove_all(tmp_raw)
	tmp, _ := os.get_absolute_path(tmp_raw, allocator)
	path :: proc(tmp, rel: string, allocator := context.allocator) -> string {
		return fmt.aprintf("%s/%s", tmp, rel, allocator = allocator)
	}
	for dir in ([]string{"top/.git", "top/a/b/.git", "top/a/b/c", "plain/x", "bare/y"}) {
		testing.expect_value(t, os.make_directory_all(path(tmp, dir, allocator)), nil)
	}
	testing.expect_value(
		t,
		os.write_entire_file(path(tmp, "top/a/odx.json", allocator), "{}"),
		nil,
	)
	testing.expect_value(t, os.make_directory(path(tmp, "plain/.git", allocator)), nil)

	cases := []struct {
		cwd, root:  string,
		has_config: bool,
	} {
		{"top/a/b/c", "top/a", true},
		{"top/a", "top/a", true},
		{"top", "top", false},
		{"plain/x", "plain", false},
		{"bare/y", "bare/y", false},
	}
	for c in cases {
		repo := find_repo(path(tmp, c.cwd, allocator), allocator)
		testing.expectf(
			t,
			repo.root == path(tmp, c.root, allocator),
			"%s: root %s",
			c.cwd,
			repo.root,
		)
		testing.expectf(
			t,
			repo.has_config == c.has_config,
			"%s: has_config %v",
			c.cwd,
			repo.has_config,
		)
	}
}
