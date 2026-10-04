package odx

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

@(private = "file")
ERROR_ENTRY :: `{"type": "error", "pos": {"file": "/r/a.odin", "offset": 9, "line": 3, "column": 5, "end_column": 6}, "msgs": ["Cannot convert '\"s\"' to 'int'"]}`

@(private = "file")
WARNING_ENTRY :: `{"type": "warning", "pos": {"file": "/r/a.odin", "offset": 70, "line": 7, "column": 2, "end_column": 5}, "msgs": ["old is deprecated: use new"]}`

@(private = "file")
SYNTAX_ENTRY :: `{"type": "warning", "pos": {"file": "/r/a.odin", "offset": 46, "line": 6, "column": 0, "end_column": 0}, "msgs": ["Syntax Error: Expected '}', got 'EOF'"]}`

@(private = "file")
NO_MSGS_ENTRY :: `{"type": "error", "pos": null, "msgs": []}`

// The compiler's own layout: one pretty-printed document and a trailing newline.
@(private = "file")
document :: proc(error_count: int, entries: ..string) -> string {
	return fmt.tprintf(
		"{{\n\t\"error_count\": %d,\n\t\"errors\": [%s]\n}}\n",
		error_count,
		strings.join(entries, ",\n", context.temp_allocator),
	)
}

@(private = "file")
outcome_name :: proc(outcome: Check_Outcome) -> string {
	switch _ in outcome {
	case Clean:
		return "clean"
	case Diagnostics:
		return "diagnostics"
	case Untrusted:
		return "untrusted"
	}
	return "nil"
}

@(test)
read_check_follows_the_decision_table :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)

	one_error := document(1, ERROR_ENTRY)
	cases := []struct {
		name:      string,
		exit_code: int,
		timed_out: bool,
		stderr:    string,
		want:      string,
		entries:   int,
	} {
		{"exit 0, empty stderr", 0, false, "", "clean", 0},
		{"exit 0, only warnings", 0, false, document(1, WARNING_ENTRY), "diagnostics", 1},
		{
			"exit 1, an error and a matching count",
			1,
			false,
			document(2, ERROR_ENTRY, WARNING_ENTRY),
			"diagnostics",
			2,
		},
		{
			"exit 1, a syntax error typed as a warning",
			1,
			false,
			document(1, SYNTAX_ENTRY),
			"diagnostics",
			1,
		},
		{
			"exit 5, a document then an assertion line",
			5,
			false,
			strings.concatenate(
				{one_error, "src/check_expr.cpp(5933): Assertion Failure: `x`\n"},
				context.temp_allocator,
			),
			"untrusted",
			0,
		},
		{"exit 11, empty stderr", 11, false, "", "untrusted", 0},
		{"exit 2, one valid document", 2, false, one_error, "untrusted", 0},
		{"a timeout after a clean exit", 0, true, "", "untrusted", 0},
		{"a timeout after a valid document", 1, true, one_error, "untrusted", 0},
		{
			"exit 1, a document then a text line",
			1,
			false,
			strings.concatenate({one_error, "trailing text\n"}, context.temp_allocator),
			"untrusted",
			0,
		},
		{
			"exit 1, two documents",
			1,
			false,
			strings.concatenate({one_error, one_error}, context.temp_allocator),
			"untrusted",
			0,
		},
		{"exit 1, empty stderr", 1, false, "", "untrusted", 0},
		{"exit 0, an error entry", 0, false, one_error, "untrusted", 0},
		{"exit 0, a syntax error entry", 0, false, document(1, SYNTAX_ENTRY), "untrusted", 0},
		{"exit 1, only warnings", 1, false, document(1, WARNING_ENTRY), "untrusted", 0},
		{
			"exit 1, a preamble line",
			1,
			false,
			strings.concatenate({"note: starting\n", one_error}, context.temp_allocator),
			"untrusted",
			0,
		},
		{
			"exit 1, error_count above the entry count",
			1,
			false,
			document(2, ERROR_ENTRY),
			"untrusted",
			0,
		},
		{
			"exit 1, error_count below the entry count",
			1,
			false,
			document(1, ERROR_ENTRY, ERROR_ENTRY),
			"untrusted",
			0,
		},
		{"exit 0, text that isn't JSON", 0, false, "this is not json\n", "untrusted", 0},
		{
			"exit 1, an entry without messages",
			1,
			false,
			document(1, NO_MSGS_ENTRY),
			"untrusted",
			0,
		},
		{"exit 1, a JSON array", 1, false, "[1, 2]\n", "untrusted", 0},
	}
	for c in cases {
		outcome := read_check(c.exit_code, c.timed_out, c.stderr, virtual.arena_allocator(&arena))
		got := outcome_name(outcome)
		testing.expectf(t, got == c.want, "%s: got %s, want %s", c.name, got, c.want)
		if d, ok := outcome.(Diagnostics); ok {
			testing.expectf(
				t,
				len(d.entries) == c.entries,
				"%s: %d entries, want %d",
				c.name,
				len(d.entries),
				c.entries,
			)
		}
		if u, ok := outcome.(Untrusted); ok {
			testing.expectf(t, u.reason != "", "%s: untrusted without a reason", c.name)
			testing.expectf(t, u.stderr == c.stderr, "%s: kept stderr %q", c.name, u.stderr)
		}
	}
}

@(test)
read_check_types_each_entry_and_keeps_its_position :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)

	stderr := document(3, ERROR_ENTRY, WARNING_ENTRY, SYNTAX_ENTRY)
	outcome := read_check(1, false, stderr, virtual.arena_allocator(&arena))
	d, ok := outcome.(Diagnostics)
	testing.expectf(t, ok, "got %s", outcome_name(outcome))
	if !ok || len(d.entries) != 3 {
		return
	}
	testing.expect_value(t, d.entries[0].kind, Entry_Kind.Error)
	testing.expect_value(t, d.entries[0].file, "/r/a.odin")
	testing.expect_value(t, d.entries[0].line, 3)
	testing.expect_value(t, d.entries[0].col, 5)
	testing.expect_value(t, len(d.entries[0].msgs), 1)
	testing.expect_value(t, d.entries[0].msgs[0], `Cannot convert '"s"' to 'int'`)
	testing.expect_value(t, d.entries[1].kind, Entry_Kind.Warning)
	testing.expect_value(t, d.entries[2].kind, Entry_Kind.Error)
	testing.expect_value(t, d.entries[2].col, 0)
}

@(private = "file", rodata)
TEST_VENDORED := [?]string{"third_party/dep"}

@(private = "file")
test_code_map :: proc(statuses: map[string]Package_Status) -> Code_Map {
	packages := make(map[string]^Package, context.temp_allocator)
	for dir, status in statuses {
		packages[dir] = new_clone(Package{dir = dir, status = status}, context.temp_allocator)
	}
	return {
		repo_root = "/repo",
		odin_root = "/odin",
		packages = packages,
		vendored = TEST_VENDORED[:],
	}
}

@(private = "file")
test_package :: proc(dir: string, files: ..Source_File) -> Package {
	pkg := Package {
		dir    = dir,
		files  = make([dynamic]Source_File, context.temp_allocator),
		status = .Strict,
	}
	append(&pkg.files, ..files)
	return pkg
}

@(test)
normalize_joins_msgs_and_relocates_an_odin_root_location_to_the_repo_caller :: proc(
	t: ^testing.T,
) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)

	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["core1"] = .Strict
	entry := Compiler_Entry {
		kind = .Error,
		file = "/odin/core/slice/slice.odin",
		line = 727,
		col  = 68,
		msgs = {
			"'where' clause evaluated to false:",
			"\tintrinsics.type_is_ordered(T)",
			"",
			"\tWith the following definitions:",
			"\t\tS :: []S;",
			"\t\tT :: S;",
			"/repo/core1/a.odin(10:6) at caller location",
		},
	}
	checked := test_package("core1", Source_File{path = "core1/a.odin"})

	got := normalize(entry, test_code_map(packages), checked, virtual.arena_allocator(&arena))

	want := Placed {
		path      = "core1/a.odin",
		line      = 10,
		col       = 6,
		message   = "'where' clause evaluated to false: intrinsics.type_is_ordered(T) With the following definitions: S :: []S; T :: S; core1/a.odin(10:6) at caller location (reported at $ODIN_ROOT/core/slice/slice.odin:727:68)",
		relocated = true,
	}
	testing.expectf(t, got == want, "got %#v\nwant %#v", got, want)
}

@(test)
normalize_keeps_a_location_with_no_caller_in_a_strict_or_pending_package :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)

	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["app"] = .Strict
	checked := test_package("app", Source_File{path = "app/app.odin"})
	code := test_code_map(packages)
	allocator := virtual.arena_allocator(&arena)

	in_vendored := Compiler_Entry {
		kind = .Error,
		file = "/repo/third_party/dep/dep.odin",
		line = 4,
		col  = 9,
		msgs = {"Cannot convert '\"s\"' to 'int'"},
	}
	got := normalize(in_vendored, code, checked, allocator)
	testing.expect_value(t, got.path, "third_party/dep/dep.odin")
	testing.expect_value(t, got.relocated, false)

	caller_outside := Compiler_Entry {
		kind = .Error,
		file = "/odin/core/slice/slice.odin",
		line = 727,
		col  = 68,
		msgs = {
			"'where' clause evaluated to false:",
			"/odin/core/x/x.odin(3:2) at caller location",
		},
	}
	got = normalize(caller_outside, code, checked, allocator)
	testing.expect_value(t, got.path, "$ODIN_ROOT/core/slice/slice.odin")
	testing.expect_value(t, got.line, 727)
	testing.expect_value(
		t,
		got.message,
		"'where' clause evaluated to false: $ODIN_ROOT/core/x/x.odin(3:2) at caller location",
	)
	testing.expect_value(t, got.relocated, false)
}

@(test)
normalize_relocates_to_the_last_caller_in_a_strict_or_pending_package :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)

	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["app"] = .Strict
	packages["wrap"] = .Pending
	checked := test_package("app", Source_File{path = "app/app.odin"})
	entry := Compiler_Entry {
		kind = .Error,
		file = "/odin/core/slice/slice.odin",
		line = 727,
		col  = 68,
		msgs = {
			"'where' clause evaluated to false:",
			"/repo/app/app.odin(10:9) at caller location",
			"/repo/wrap/wrap.odin(6:9) at caller location",
			"/odin/core/fmt/fmt.odin(1:1) at caller location",
		},
	}

	got := normalize(entry, test_code_map(packages), checked, virtual.arena_allocator(&arena))

	testing.expect_value(t, got.path, "wrap/wrap.odin")
	testing.expect_value(t, got.line, 6)
	testing.expect_value(t, got.col, 9)
	testing.expect_value(t, got.relocated, true)
}

@(test)
normalize_deletes_internal_ids :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)

	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["s1"] = .Strict
	checked := test_package("s1", Source_File{path = "s1/a.odin"})
	messages: [2]string
	for id, i in ([]string{"34!85", "33!121"}) {
		entry := Compiler_Entry {
			kind = .Error,
			file = "/repo/s1/a.odin",
			line = 7,
			col  = 19,
			msgs = {
				fmt.tprintf(
					"Cannot assign value 'proc(a: string, b: int) -> bool {{...}} /* %s */' of type 'proc(string, int) -> bool'",
					id,
				),
				"\tNote: The input parameter types differ",
			},
		}
		messages[i] =
			normalize(entry, test_code_map(packages), checked, virtual.arena_allocator(&arena)).message
	}
	want := "Cannot assign value 'proc(a: string, b: int) -> bool {...}' of type 'proc(string, int) -> bool' Note: The input parameter types differ"
	testing.expect_value(t, messages[0], want)
	testing.expect_value(t, messages[1], want)
}

@(test)
normalize_places_line_0_and_column_0_and_a_null_pos :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)

	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["app"] = .Strict
	checked := test_package(
		"app",
		Source_File{path = "app/a.odin"},
		Source_File{path = "app/b.odin"},
	)
	code := test_code_map(packages)
	allocator := virtual.arena_allocator(&arena)

	line_0 := normalize(
		Compiler_Entry{.Error, "/repo/app/b.odin", 0, 5, {"m"}},
		code,
		checked,
		allocator,
	)
	testing.expect_value(t, line_0, Placed{path = "app/b.odin", line = 1, col = 1, message = "m"})

	col_0 := normalize(
		Compiler_Entry{.Error, "/repo/app/b.odin", 6, 0, {"Syntax Error: x"}},
		code,
		checked,
		allocator,
	)
	testing.expect_value(
		t,
		col_0,
		Placed{path = "app/b.odin", line = 6, col = 1, message = "Syntax Error: x"},
	)

	null_pos := normalize(
		Compiler_Entry{.Error, "", 0, 0, {"Undefined entry point procedure 'main'"}},
		code,
		checked,
		allocator,
	)
	testing.expect_value(
		t,
		null_pos,
		Placed {
			path = "app/a.odin",
			line = 1,
			col = 1,
			message = "Undefined entry point procedure 'main'",
		},
	)
}

@(test)
normalize_maps_a_real_path_back_to_the_checked_packages_link :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)

	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["pkg"] = .Strict
	checked := test_package(
		"pkg",
		Source_File{path = "pkg/link.odin", link_target = "/repo/.src/real.odin"},
		Source_File{path = "pkg/ok.odin"},
	)
	entry := Compiler_Entry{.Error, "/repo/.src/real.odin", 4, 2, {"bad"}}

	got := normalize(entry, test_code_map(packages), checked, virtual.arena_allocator(&arena))

	testing.expect_value(
		t,
		got,
		Placed{path = "pkg/link.odin", line = 4, col = 2, message = "bad"},
	)
}

@(test)
code_map_realpaths_a_symlinked_repo_root :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)
	allocator := virtual.arena_allocator(&arena)

	tmp, err := os.make_directory_temp("", "odx-code-map-*", allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(tmp)
	real_dir := fmt.aprintf("%s/real", tmp, allocator = allocator)
	link_dir := fmt.aprintf("%s/link", tmp, allocator = allocator)
	testing.expect_value(t, os.make_directory(real_dir), nil)
	testing.expect_value(t, os.make_directory(fmt.tprintf("%s/app", real_dir)), nil)
	testing.expect_value(t, os.symlink(real_dir, link_dir), nil)
	real_root, real_err := os.get_absolute_path(real_dir, allocator)
	testing.expect_value(t, real_err, nil)

	checked := test_package("app", Source_File{path = "app/a.odin"})
	code := make_code_map(link_dir, "/odin", {checked}, {}, allocator)
	entry := Compiler_Entry{.Error, fmt.tprintf("%s/app/a.odin", real_root), 2, 3, {"bad"}}

	got := normalize(entry, code, checked, allocator)

	testing.expect_value(t, got.path, "app/a.odin")
}

@(test)
owner_of_keeps_errors_everywhere_and_warnings_where_the_team_owns_code :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["app"] = .Strict
	packages["lib"] = .Pending
	code := test_code_map(packages)

	cases := []struct {
		kind:  Entry_Kind,
		path:  string,
		kept:  bool,
		owner: string,
	} {
		{.Error, "app/a.odin", true, "app"},
		{.Error, "lib/a.odin", true, "lib"},
		{.Error, "third_party/dep/dep.odin", true, ""},
		{.Error, "$ODIN_ROOT/core/fmt/fmt.odin", true, ""},
		{.Warning, "app/a.odin", true, "app"},
		{.Warning, "lib/a.odin", true, "lib"},
		{.Warning, "third_party/dep/dep.odin", false, ""},
		{.Warning, "third_party/dep/inner/x.odin", false, ""},
		{.Warning, "$ODIN_ROOT/core/fmt/fmt.odin", false, ""},
	}
	for c in cases {
		owner, kept := owner_of(c.kind, c.path, code)
		got_owner := owner.dir if owner != nil else ""
		testing.expectf(
			t,
			kept == c.kept && got_owner == c.owner,
			"%v at %s: kept %v by %q, want %v by %q",
			c.kind,
			c.path,
			kept,
			got_owner,
			c.kept,
			c.owner,
		)
	}
}

@(test)
mutes_only_on_an_unrelocated_error_in_the_checked_packages_own_files :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	checked := test_package("app", Source_File{path = "app/a.odin"})
	own := Placed {
		path = "app/a.odin",
		line = 1,
		col  = 1,
	}
	relocated := own
	relocated.relocated = true
	elsewhere := own
	elsewhere.path = "lib/a.odin"

	testing.expect(t, mutes(.Error, own, checked))
	testing.expect(t, !mutes(.Warning, own, checked))
	testing.expect(t, !mutes(.Error, relocated, checked))
	testing.expect(t, !mutes(.Error, elsewhere, checked))
}

@(test)
settle_redeclarations_gives_one_report_whatever_order_the_compiler_used :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	defer free_all(context.temp_allocator)
	allocator := virtual.arena_allocator(&arena)

	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["tools"] = .Strict
	code := test_code_map(packages)
	checked := test_package("tools", Source_File{path = "tools/a.odin"})
	in_scope :: proc(file: string, line: int, at: ..string) -> Compiler_Entry {
		msgs := make([dynamic]string, context.temp_allocator)
		append(&msgs, "Redeclaration of 'main' in this scope")
		for a in at {
			append(&msgs, fmt.tprintf("\tat /repo/tools/%s", a))
		}
		return {.Error, fmt.tprintf("/repo/tools/%s", file), line, 1, msgs[:]}
	}
	entry_point :: proc(file: string, line: int) -> Compiler_Entry {
		msgs := make([]string, 1, context.temp_allocator)
		msgs[0] = "Redeclaration of the entry pointer procedure 'main'"
		return {.Error, fmt.tprintf("/repo/tools/%s", file), line, 1, msgs}
	}
	// Two orders the compiler produced for one package in lane 7, plus a local redeclaration.
	runs := [][]Compiler_Entry {
		{in_scope("b.odin", 64, "a.odin(24:1)"), in_scope("c.odin", 64, "a.odin(24:1)")},
		{
			entry_point("a.odin", 24),
			entry_point("b.odin", 64),
			in_scope("c.odin", 64, "b.odin(64:1)", "a.odin(24:1)"),
		},
	}
	want := []Placed {
		{
			path = "tools/b.odin",
			line = 64,
			col = 1,
			message = "Redeclaration of 'main' in this scope at tools/a.odin(24:1)",
		},
		{
			path = "tools/c.odin",
			line = 64,
			col = 1,
			message = "Redeclaration of 'main' in this scope at tools/a.odin(24:1)",
		},
	}
	for entries, i in runs {
		records := make([dynamic]Redeclaration, context.temp_allocator)
		for e in entries {
			r, ok := read_redeclaration(e, normalize(e, code, checked, allocator), code, allocator)
			testing.expectf(t, ok, "run %d: not read as a redeclaration: %v", i, e.msgs)
			append(&records, r)
		}
		got := settle_redeclarations(records[:], allocator)
		testing.expectf(t, slice.equal(got, want), "run %d:\ngot  %#v\nwant %#v", i, got, want)
	}

	local := in_scope("a.odin", 9, "a.odin(8:2)")
	r, ok := read_redeclaration(local, normalize(local, code, checked, allocator), code, allocator)
	testing.expect(t, ok)
	got := settle_redeclarations({r}, allocator)
	testing.expect_value(t, len(got), 1)
	if len(got) == 1 {
		testing.expect_value(t, got[0].path, "tools/a.odin")
		testing.expect_value(t, got[0].line, 9)
		testing.expect_value(
			t,
			got[0].message,
			"Redeclaration of 'main' in this scope at tools/a.odin(8:2)",
		)
	}

	alone := entry_point("a.odin", 24)
	r, ok = read_redeclaration(alone, normalize(alone, code, checked, allocator), code, allocator)
	testing.expect(t, ok)
	got = settle_redeclarations({r}, allocator)
	testing.expect_value(t, len(got), 1)
	if len(got) == 1 {
		testing.expect_value(
			t,
			got[0].message,
			"Redeclaration of the entry pointer procedure 'main'",
		)
	}

	other := Compiler_Entry{.Error, "/repo/tools/a.odin", 3, 1, {"Cannot convert"}}
	_, ok = read_redeclaration(other, normalize(other, code, checked, allocator), code, allocator)
	testing.expect(t, !ok)
}
