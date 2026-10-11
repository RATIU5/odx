package odx

import "core:slice"
import "core:testing"

@(test)
add_rule_finding_mutes_and_holds_back_by_the_rule_table :: proc(t: ^testing.T) {
	cases := []struct {
		rule:      Rule,
		status:    Package_Status,
		muted:     bool,
		added:     bool,
		held_back: bool,
	} {
		{.Line_Length, .Strict, false, true, false},
		{.Line_Length, .Pending, false, true, true},
		{.Line_Length, .Pending, true, false, false},
		{.Ignore_Invalid, .Pending, true, true, true},
		{.Ignore_Unused, .Pending, false, true, true},
		{.Ignore_Unused, .Strict, true, false, false},
		{.Import_Escape, .Pending, true, true, false},
		{.Path_Case, .Pending, false, true, false},
		{.Parse_Unsupported, .Pending, false, true, false},
		{.Odin, .Pending, true, true, false},
		{.Odin, .Pending, false, true, false},
		{.Odin, .Strict, false, true, false},
		{.Pending_Stale, .Strict, false, true, false},
		{.Format, .Strict, false, true, false},
		{.Format, .Pending, false, true, true},
		{.Format, .Strict, true, false, false},
		{.Name_Case, .Pending, false, true, true},
		{.Name_Case, .Strict, true, false, false},
		{.Package_Name, .Strict, false, true, false},
		{.Package_Name, .Strict, true, false, false},
		{.File_Name, .Pending, false, true, true},
		{.Import_Alias, .Strict, true, false, false},
		{.Import_Order, .Pending, false, true, true},
	}
	for c in cases {
		result: Result
		pkg := Package {
			dir    = "lib",
			status = c.status,
			muted  = c.muted,
		}
		add_rule_finding(&result, &pkg, Finding{path = "a.odin", line = 1, col = 1, rule = c.rule})
		added := len(result.findings) == 1
		held_back := added && result.findings[0].held_back
		owned := added && result.findings[0].owner_dir == pkg.dir
		delete(result.findings)
		testing.expectf(
			t,
			added == c.added && held_back == c.held_back && owned == c.added,
			"%v on %v (muted %v): added %v held back %v, want %v %v",
			c.rule,
			c.status,
			c.muted,
			added,
			held_back,
			c.added,
			c.held_back,
		)
	}
}

@(test)
add_rule_finding_adds_an_unowned_finding_as_shown :: proc(t: ^testing.T) {
	result: Result
	defer delete(result.findings)
	add_rule_finding(&result, nil, Finding{path = "/elsewhere/a.odin", rule = .Odin})
	testing.expect_value(t, len(result.findings), 1)
	if len(result.findings) == 1 {
		testing.expect_value(t, result.findings[0].held_back, false)
		testing.expect_value(t, result.findings[0].owner_dir, "")
	}
}

@(test)
add_rule_finding_keeps_a_held_back_finding_held_back_in_a_strict_package :: proc(t: ^testing.T) {
	result: Result
	defer delete(result.findings)
	pkg := Package {
		dir    = "lib",
		status = .Strict,
	}
	finding := Finding {
		path      = "lib/a.odin",
		rule      = .Odin,
		held_back = true,
	}
	add_rule_finding(&result, &pkg, finding)
	testing.expect_value(t, len(result.findings), 1)
	if len(result.findings) == 1 {
		testing.expect_value(t, result.findings[0].held_back, true)
		testing.expect_value(t, result.findings[0].owner_dir, "lib")
	}
}

@(test)
rules_table_matches_the_contract_flag_by_flag :: proc(t: ^testing.T) {
	want := [Rule]Rule_Info {
		.Odin                   = {"odin", false, true, false, false},
		.Parse_Unsupported      = {"parse-unsupported", false, true, false, false},
		.Import_Escape          = {"import-escape", false, true, false, true},
		.Path_Case              = {"path-case", false, true, false, true},
		.Line_Length            = {"line-length", true, false, true, false},
		.Ignore_Invalid         = {"ignore-invalid", false, true, true, false},
		.Ignore_Unused          = {"ignore-unused", false, false, true, false},
		.Pending_Stale          = {"pending-stale", false, true, false, false},
		.Block_Comment          = {"block-comment", false, false, true, true},
		.One_Line_Block         = {"one-line-block", false, false, true, true},
		.Auto_Cast              = {"auto-cast", false, false, true, true},
		.Fallthrough            = {"fallthrough", true, false, true, true},
		.Bounds_Check_Directive = {"bounds-check-directive", true, false, true, true},
		.Vet_Disabled           = {"vet-disabled", false, false, true, false},
		.Feature_Relaxed        = {"feature-relaxed", true, false, true, false},
		.Transmute              = {"transmute", true, false, true, true},
		.Format                 = {"format", false, false, true, true},
		.Proc_Length            = {"proc-length", true, false, true, true},
		.Nesting_Depth          = {"nesting-depth", true, false, true, true},
		.Name_Case              = {"name-case", true, false, true, true},
		.Package_Name           = {"package-name", false, false, true, false},
		.File_Name              = {"file-name", false, false, true, false},
		.Import_Alias           = {"import-alias", false, false, true, true},
		.Import_Order           = {"import-order", false, false, true, true},
	}
	for got, rule in RULES {
		w := want[rule]
		testing.expectf(t, got.id == w.id, "%v: id %q, want %q", rule, got.id, w.id)
		testing.expectf(
			t,
			got.ignorable == w.ignorable,
			"%s: ignorable %v, want %v",
			w.id,
			got.ignorable,
			w.ignorable,
		)
		testing.expectf(
			t,
			got.runs_when_muted == w.runs_when_muted,
			"%s: runs when muted %v, want %v",
			w.id,
			got.runs_when_muted,
			w.runs_when_muted,
		)
		testing.expectf(
			t,
			got.held_back == w.held_back,
			"%s: held back %v, want %v",
			w.id,
			got.held_back,
			w.held_back,
		)
		testing.expectf(
			t,
			got.needs_parse == w.needs_parse,
			"%s: needs parse %v, want %v",
			w.id,
			got.needs_parse,
			w.needs_parse,
		)
	}
}

@(test)
add_rule_finding_counts_what_a_muted_package_hides :: proc(t: ^testing.T) {
	cases := []struct {
		rule:        Rule,
		muted:       bool,
		line:        int,
		muted_count: int,
	} {
		{.Name_Case, true, 9, 1},
		{.Format, true, 9, 1},
		{.Ignore_Unused, true, 9, 1},
		{.Name_Case, false, 9, 0},
		{.Odin, true, 9, 0},
		{.Ignore_Invalid, true, 9, 0},
		// Line 3 is under an ignore for `name-case` alone.
		{.Name_Case, true, 3, 0},
		{.Proc_Length, true, 3, 1},
	}
	for c in cases {
		result: Result
		defer delete(result.findings)
		covers := [1]Line_Run{{3, 3}}
		ignores := [1]Ignore{{line = 2, col = 1, rules = {.Name_Case}, covers = covers[:]}}
		files := [1]Source_File{{path = "lib/a.odin"}}
		pkg := Package {
			dir   = "lib",
			muted = c.muted,
			files = slice.into_dynamic(files[:]),
		}
		append(&pkg.files, files[0])
		pkg.files[0].ignores = slice.into_dynamic(ignores[:])
		append(&pkg.files[0].ignores, ignores[0])
		add_rule_finding(
			&result,
			&pkg,
			Finding{path = "lib/a.odin", line = c.line, col = 1, rule = c.rule},
		)
		testing.expectf(
			t,
			pkg.muted_count == c.muted_count,
			"%v at line %d (muted %v): muted_count %d, want %d",
			c.rule,
			c.line,
			c.muted,
			pkg.muted_count,
			c.muted_count,
		)
		covered := c.muted && c.rule == .Name_Case && c.line == 3
		testing.expectf(
			t,
			pkg.files[0].ignores[0].used == covered,
			"%v at line %d (muted %v): the ignore is used %v",
			c.rule,
			c.line,
			c.muted,
			pkg.files[0].ignores[0].used,
		)
	}
}

@(test)
note_muted_notes_each_package_with_a_dropped_finding_in_package_order :: proc(t: ^testing.T) {
	packages := []Package {
		{dir = ".", muted = true, muted_count = 1},
		{dir = "a", muted = true},
		{dir = "b", muted = true, muted_count = 2, status = .Pending},
		{dir = "c"},
	}
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	result: Result
	note_muted(packages, &result)
	want := []Note {
		{text = "odx: .: compile errors hide this package's other findings"},
		{"odx: b: compile errors hide this package's other findings", true},
	}
	testing.expectf(t, slice.equal(result.notes[:], want), "got %v", result.notes)
}

@(test)
note_test_tagged_counts_each_package_s_test_tagged_files_in_package_order :: proc(t: ^testing.T) {
	files :: proc(tagged: ..bool) -> [dynamic]Source_File {
		list := make([dynamic]Source_File, context.temp_allocator)
		for is_test in tagged {
			append(&list, Source_File{is_test = is_test, targets = ALL_TARGETS})
		}
		return list
	}
	defer free_all(context.temp_allocator)
	packages := []Package {
		{dir = ".", files = files(false, true)},
		{dir = "a", files = files(false, false)},
		{dir = "b", files = files(true, true, false, true), status = .Pending},
		{dir = "c", files = files(true), compile = Skipped{}},
		{dir = "d", files = files()},
	}
	context.allocator = context.temp_allocator
	result: Result
	note_test_tagged(packages, &result)
	want := []Note {
		{text = "odx: .: the compiler doesn't check 1 files tagged #+test"},
		{"odx: b: the compiler doesn't check 3 files tagged #+test", true},
		{text = "odx: c: the compiler doesn't check 1 files tagged #+test"},
	}
	testing.expectf(t, slice.equal(result.notes[:], want), "got %v", result.notes)
}
