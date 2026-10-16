package odx

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

@(private = "file")
ERROR_ENTRY ::
	`{"type": "error", "pos": {"file": "/r/a.odin", "offset": 9, "line": 3, "column": 5, ` +
	`"end_column": 6}, "msgs": ["Cannot convert '\"s\"' to 'int'"]}`

@(private = "file")
WARNING_ENTRY ::
	`{"type": "warning", "pos": {"file": "/r/a.odin", "offset": 70, "line": 7, "column": 2, ` +
	`"end_column": 5}, "msgs": ["old is deprecated: use new"]}`

@(private = "file")
SYNTAX_ENTRY ::
	`{"type": "warning", "pos": {"file": "/r/a.odin", "offset": 46, "line": 6, "column": 0, ` +
	`"end_column": 0}, "msgs": ["Syntax Error: Expected '}', got 'EOF'"]}`

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
	case Entries:
		return "entries"
	case Untrusted:
		return "untrusted"
	}
	return "nil"
}

@(private = "file")
Read_Case :: struct {
	name:      string,
	exit_code: int,
	timed_out: bool,
	stderr:    string,
	want:      string,
	entries:   int,
}

@(private = "file")
expect_read_cases :: proc(t: ^testing.T, cases: []Read_Case) {
	for c in cases {
		outcome := read_check(
			Exited{c.exit_code},
			c.timed_out,
			false,
			c.stderr,
			context.temp_allocator,
		)
		got := outcome_name(outcome)
		testing.expectf(t, got == c.want, "%s: got %s, want %s", c.name, got, c.want)
		if d, ok := outcome.(Entries); ok {
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
			// A timeout's message names the limit instead.
			has_reason := u.reason != "" || c.timed_out
			testing.expectf(t, has_reason, "%s: untrusted without a reason", c.name)
			testing.expectf(t, u.stderr == c.stderr, "%s: kept stderr %q", c.name, u.stderr)
		}
	}
}

@(test)
read_check_trusts_a_run_whose_exit_code_fits_its_document :: proc(t: ^testing.T) {
	cases := []Read_Case {
		{"exit 0, empty stderr", 0, false, "", "clean", 0},
		{"exit 0, only warnings", 0, false, document(1, WARNING_ENTRY), "entries", 1},
		{
			"exit 1, an error and a matching count",
			1,
			false,
			document(2, ERROR_ENTRY, WARNING_ENTRY),
			"entries",
			2,
		},
		{
			"exit 1, a syntax error typed as a warning",
			1,
			false,
			document(1, SYNTAX_ENTRY),
			"entries",
			1,
		},
	}
	expect_read_cases(t, cases)
}

@(test)
read_check_distrusts_every_other_run :: proc(t: ^testing.T) {
	one_error := document(1, ERROR_ENTRY)
	cases := []Read_Case {
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
	expect_read_cases(t, cases)
}

@(test)
read_check_calls_a_signal_a_signal_and_an_exit_code_an_exit_code :: proc(t: ^testing.T) {
	one_error := document(1, ERROR_ENTRY)
	cases := []struct {
		name:      string,
		status:    Child_Status,
		timed_out: bool,
		retried:   bool,
		stderr:    string,
		reason:    string,
	} {
		{"SIGSEGV on the second run", Signaled{11}, false, true, "", "died by signal 11 twice"},
		{"SIGSEGV on a run nobody retries", Signaled{11}, false, false, "", "died by signal 11"},
		{"exit code 11", Exited{11}, false, false, "", "ended with exit code 11"},
		{"exit code 11 on the second run", Exited{11}, false, true, "", "ended with exit code 11"},
		{
			"SIGTRAP after a document",
			Signaled{5},
			false,
			true,
			one_error,
			"died by signal 5 twice",
		},
		{"odx's own kill at the limit", Signaled{9}, true, false, "", ""},
		{"the limit on the second run", Signaled{9}, true, true, "", ""},
	}
	for c in cases {
		outcome := read_check(c.status, c.timed_out, c.retried, c.stderr, context.temp_allocator)
		u, untrusted := outcome.(Untrusted)
		testing.expectf(t, untrusted, "%s: got %s", c.name, outcome_name(outcome))
		testing.expectf(
			t,
			u.reason == c.reason,
			"%s: reason %q, want %q",
			c.name,
			u.reason,
			c.reason,
		)
		testing.expectf(t, u.stderr == c.stderr, "%s: kept stderr %q", c.name, u.stderr)
	}
}

@(test)
read_check_reads_a_second_run_like_a_first :: proc(t: ^testing.T) {
	allocator := context.temp_allocator

	_, clean := read_check(Exited{0}, false, true, "", allocator).(Clean)
	testing.expect(t, clean, "a clean second run isn't clean")
	d, has := read_check(Exited{1}, false, true, document(1, ERROR_ENTRY), allocator).(Entries)
	testing.expect(t, has && len(d.entries) == 1, "a second run lost its entries")
}

@(test)
read_check_types_each_entry_and_keeps_its_position :: proc(t: ^testing.T) {
	stderr := document(3, ERROR_ENTRY, WARNING_ENTRY, SYNTAX_ENTRY)
	outcome := read_check(Exited{1}, false, false, stderr, context.temp_allocator)
	d, ok := outcome.(Entries)
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

	got := normalize(entry, test_code_map(packages), checked, context.temp_allocator)

	MESSAGE ::
		"'where' clause evaluated to false: intrinsics.type_is_ordered(T) " +
		"With the following definitions: S :: []S; T :: S; " +
		"core1/a.odin(10:6) at caller location " +
		"(reported at $ODIN_ROOT/core/slice/slice.odin:727:68)"
	want := Placed {
		path      = "core1/a.odin",
		line      = 10,
		col       = 6,
		message   = MESSAGE,
		relocated = true,
	}
	testing.expectf(t, got == want, "got %#v\nwant %#v", got, want)
}

@(test)
normalize_keeps_a_location_with_no_caller_in_a_strict_or_pending_package :: proc(t: ^testing.T) {
	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["app"] = .Strict
	checked := test_package("app", Source_File{path = "app/app.odin"})
	code := test_code_map(packages)
	allocator := context.temp_allocator

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

	got := normalize(entry, test_code_map(packages), checked, context.temp_allocator)

	testing.expect_value(t, got.path, "wrap/wrap.odin")
	testing.expect_value(t, got.line, 6)
	testing.expect_value(t, got.col, 9)
	testing.expect_value(t, got.relocated, true)
}

@(test)
normalize_deletes_internal_ids :: proc(t: ^testing.T) {
	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["s1"] = .Strict
	checked := test_package("s1", Source_File{path = "s1/a.odin"})
	messages: [2]string
	for id, i in ([]string{"s1:a.odin!85", "s1:b c.odin!121"}) {
		entry := Compiler_Entry {
			kind = .Error,
			file = "/repo/s1/a.odin",
			line = 7,
			col  = 19,
			msgs = {
				fmt.tprintf(
					"Cannot assign value 'proc(a: string, b: int) -> bool {{...}} /* %s */' " +
					"of type 'proc(string, int) -> bool'",
					id,
				),
				"\tNote: The input parameter types differ",
			},
		}
		placed := normalize(entry, test_code_map(packages), checked, context.temp_allocator)
		messages[i] = placed.message
	}
	want :=
		"Cannot assign value 'proc(a: string, b: int) -> bool {...}' " +
		"of type 'proc(string, int) -> bool' Note: The input parameter types differ"
	testing.expect_value(t, messages[0], want)
	testing.expect_value(t, messages[1], want)

	for kept in ([]string{"a /* note */ b", "a /* 34!85 */ b", "a /* s1:a.odin!x */ b", "a /* b"}) {
		entry := Compiler_Entry{.Error, "/repo/s1/a.odin", 7, 19, {kept}}
		placed := normalize(entry, test_code_map(packages), checked, context.temp_allocator)
		testing.expect_value(t, placed.message, kept)
	}
}

@(test)
normalize_places_line_0_and_column_0_and_a_null_pos :: proc(t: ^testing.T) {
	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["app"] = .Strict
	checked := test_package(
		"app",
		Source_File{path = "app/a.odin"},
		Source_File{path = "app/b.odin"},
	)
	code := test_code_map(packages)
	allocator := context.temp_allocator

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
	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["pkg"] = .Strict
	checked := test_package(
		"pkg",
		Source_File{path = "pkg/link.odin", link_target = "/repo/.src/real.odin"},
		Source_File{path = "pkg/ok.odin"},
	)
	entry := Compiler_Entry{.Error, "/repo/.src/real.odin", 4, 2, {"bad"}}

	got := normalize(entry, test_code_map(packages), checked, context.temp_allocator)

	testing.expect_value(
		t,
		got,
		Placed{path = "pkg/link.odin", line = 4, col = 2, message = "bad"},
	)
}

@(test)
code_map_realpaths_a_symlinked_repo_root :: proc(t: ^testing.T) {
	allocator := context.temp_allocator

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
	SUGGESTION ::
		"\tSuggestion: Is this a single-file package? " +
		"If so, try compiling using the `-file` flag."
	allocator := context.temp_allocator

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
		msgs := make([]string, 2, context.temp_allocator)
		msgs[0] = "Redeclaration of the entry point procedure 'main'"
		msgs[1] = SUGGESTION
		return {.Error, fmt.tprintf("/repo/tools/%s", file), line, 1, msgs}
	}
	// The compiler ends each entry about a `main` in package main with this line.
	suggested :: proc(entry: Compiler_Entry) -> Compiler_Entry {
		msgs := make([dynamic]string, context.temp_allocator)
		append(&msgs, ..entry.msgs)
		append(&msgs, SUGGESTION)
		return {entry.kind, entry.file, entry.line, entry.col, msgs[:]}
	}
	// Two orders the compiler may use for one package, plus a local redeclaration.
	runs := [][]Compiler_Entry {
		{
			suggested(in_scope("b.odin", 64, "a.odin(24:1)")),
			suggested(in_scope("c.odin", 64, "a.odin(24:1)")),
		},
		{
			entry_point("b.odin", 64),
			suggested(in_scope("c.odin", 64, "b.odin(64:1)", "a.odin(24:1)")),
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
			"Redeclaration of the entry point procedure 'main' " + SUGGESTION[1:],
		)
	}

	other := Compiler_Entry{.Error, "/repo/tools/a.odin", 3, 1, {"Cannot convert"}}
	_, ok = read_redeclaration(other, normalize(other, code, checked, allocator), code, allocator)
	testing.expect(t, !ok)
}

@(test)
settle_duplicate_packages_gives_one_finding_at_the_first_site_whatever_the_order :: proc(
	t: ^testing.T,
) {
	allocator := context.temp_allocator

	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["app"] = .Strict
	code := test_code_map(packages)
	checked := test_package("app", Source_File{path = "app/a.odin"})
	// The compiler's entry for a `util` at `at` that it read after the one at `named`.
	duplicate :: proc(at, named: string) -> Compiler_Entry {
		msgs := make([]string, 4, context.temp_allocator)
		msgs[0] = "Duplicate declaration of 'package util'"
		msgs[1] = "\tA package name must be unique"
		msgs[2] = "\tA package name is required for link name prefixing to have a consistent ABI"
		msgs[3] = fmt.tprintf("/repo/%s/util/f0.odin(1:1) found at previous location", named)
		return {.Error, fmt.tprintf("/repo/%s/util/f0.odin", at), 1, 1, msgs}
	}
	TEXT ::
		"Duplicate declaration of 'package util' A package name must be unique " +
		"A package name is required for link name prefixing to have a consistent ABI"
	PAIR :: TEXT + " b/util/f0.odin(1:1) found at previous location"
	TRIPLE :: PAIR + " c/util/f0.odin(1:1) found at previous location"
	OTHER_PAIR :: TEXT + " y/util/f0.odin(1:1) found at previous location"
	cases := []struct {
		name:    string,
		entries: []Compiler_Entry,
		want:    []Placed,
	} {
		{
			"a pair, reported at the second in path order",
			{duplicate("b", "a")},
			{{path = "a/util/f0.odin", line = 1, col = 1, message = PAIR}},
		},
		{
			"a pair, reported at the first in path order",
			{duplicate("a", "b")},
			{{path = "a/util/f0.odin", line = 1, col = 1, message = PAIR}},
		},
		{
			"a pair that two checks reported in both orders",
			{duplicate("a", "b"), duplicate("b", "a"), duplicate("b", "a")},
			{{path = "a/util/f0.odin", line = 1, col = 1, message = PAIR}},
		},
		{
			"a triple, each later one naming the first",
			{duplicate("b", "a"), duplicate("c", "a")},
			{{path = "a/util/f0.odin", line = 1, col = 1, message = TRIPLE}},
		},
		{
			"a triple the compiler read last to first",
			{duplicate("b", "c"), duplicate("a", "c")},
			{{path = "a/util/f0.odin", line = 1, col = 1, message = TRIPLE}},
		},
		{
			"a triple, each naming the one before it",
			{duplicate("c", "b"), duplicate("b", "a")},
			{{path = "a/util/f0.odin", line = 1, col = 1, message = TRIPLE}},
		},
		{
			"two pairs that share no site",
			{duplicate("y", "x"), duplicate("a", "b")},
			{
				{path = "x/util/f0.odin", line = 1, col = 1, message = OTHER_PAIR},
				{path = "a/util/f0.odin", line = 1, col = 1, message = PAIR},
			},
		},
		{"no entry", {}, {}},
	}
	for c in cases {
		records := make([dynamic]Duplicate_Package, context.temp_allocator)
		for e in c.entries {
			d, ok := read_duplicate_package(
				e,
				normalize(e, code, checked, allocator),
				code,
				allocator,
			)
			testing.expectf(t, ok, "%s: not read as a duplicate package: %v", c.name, e.msgs)
			append(&records, d)
		}
		got, of := settle_duplicate_packages(records[:], allocator)
		testing.expectf(t, slice.equal(got, c.want), "%s: got %v", c.name, got)
		testing.expectf(
			t,
			len(of) == len(records),
			"%s: %d records in %v",
			c.name,
			len(records),
			of,
		)
		for g, i in of {
			site := records[i].placed.path
			linked := site == got[g].path || strings.contains(got[g].message, site)
			testing.expectf(t, linked, "%s: record %d at %s is in finding %d", c.name, i, site, g)
		}
	}
}

// By path alone, `$ODIN_ROOT/...` sorts before `util`.
@(test)
settle_duplicate_packages_reports_in_the_repo_then_the_odin_root :: proc(t: ^testing.T) {
	allocator := context.temp_allocator
	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["util"] = .Strict
	packages["app"] = .Strict
	code := test_code_map(packages)
	checked := test_package("app", Source_File{path = "app/a.odin"})
	CHECKED :: "util/u.odin"
	LATER_CHECKED :: "zlib/z.odin"
	ROOT :: "$ODIN_ROOT/core/util/u.odin"
	LATER_ROOT :: "$ODIN_ROOT/vendor/util/u.odin"
	cases := []struct {
		name:  string,
		// In the order the finding names them, the first being where it lies.
		sites: []string,
	} {
		{"checked and the Odin root", {CHECKED, ROOT}},
		{"two of each", {CHECKED, LATER_CHECKED, ROOT, LATER_ROOT}},
		{"every site under the Odin root", {ROOT, LATER_ROOT}},
	}
	absolute :: proc(site: string) -> string {
		if strings.has_prefix(site, ODIN_ROOT_PREFIX) {
			return fmt.tprintf("/odin/%s", site[len(ODIN_ROOT_PREFIX):])
		}
		return fmt.tprintf("/repo/%s", site)
	}
	for c in cases {
		want := strings.builder_make(context.temp_allocator)
		strings.write_string(&want, "Duplicate declaration of 'package util'")
		for site in c.sites[1:] {
			fmt.sbprintf(&want, " %s(1:1) found at previous location", site)
		}
		// Each site but one is reported once, naming the one before it or the one after it, so
		// every order the compiler can read the packages in gives the same links.
		for forward in ([]bool{true, false}) {
			records := make([dynamic]Duplicate_Package, context.temp_allocator)
			for i in 1 ..< len(c.sites) {
				at, named := c.sites[i], c.sites[i - 1]
				if !forward {
					at, named = named, at
				}
				msgs := make([]string, 2, context.temp_allocator)
				msgs[0] = "Duplicate declaration of 'package util'"
				msgs[1] = fmt.tprintf("%s(1:1) found at previous location", absolute(named))
				e := Compiler_Entry{.Error, absolute(at), 1, 1, msgs}
				d, ok := read_duplicate_package(
					e,
					normalize(e, code, checked, allocator),
					code,
					allocator,
				)
				testing.expectf(t, ok, "%s: not read as a duplicate package", c.name)
				append(&records, d)
			}
			got, _ := settle_duplicate_packages(records[:], allocator)
			if !testing.expectf(t, len(got) == 1, "%s: %d findings", c.name, len(got)) {
				continue
			}
			testing.expectf(
				t,
				got[0].path == c.sites[0],
				"%s, forward %v: reported at %s",
				c.name,
				forward,
				got[0].path,
			)
			testing.expectf(
				t,
				got[0].message == strings.to_string(want),
				"%s, forward %v: message %q",
				c.name,
				forward,
				got[0].message,
			)
		}
	}
}

@(test)
read_duplicate_package_takes_only_the_compilers_duplicate_package_entry :: proc(t: ^testing.T) {
	allocator := context.temp_allocator
	packages := make(map[string]Package_Status, context.temp_allocator)
	packages["app"] = .Strict
	code := test_code_map(packages)
	checked := test_package("app", Source_File{path = "app/a.odin"})
	cases := []struct {
		name: string,
		msgs: []string,
	} {
		{
			"a redeclared name",
			{"Redeclaration of 'main' in this scope", "\tat /repo/app/b.odin(2:1)"},
		},
		{"the message alone", {"Duplicate declaration of 'package util'"}},
		{
			"a last line that names no position",
			{"Duplicate declaration of 'package util'", "\tA package name must be unique"},
		},
		{
			"a position odx can't read",
			{"Duplicate declaration of 'package util'", "somewhere found at previous location"},
		},
		{
			"a duplicate of something that isn't a package",
			{"Duplicate declaration of 'x'", "/repo/app/b.odin(2:1) found at previous location"},
		},
	}
	for c in cases {
		entry := Compiler_Entry{.Error, "/repo/app/a.odin", 1, 1, c.msgs}
		_, ok := read_duplicate_package(
			entry,
			normalize(entry, code, checked, allocator),
			code,
			allocator,
		)
		testing.expectf(t, !ok, "%s: read as a duplicate package", c.name)
	}
}
