package odx

import "core:slice"
import "core:testing"

@(test)
add_rule_finding_mutes_and_holds_back_by_the_rule_table :: proc(t: ^testing.T) {
	cases := []struct {
		rule:        Rule,
		status:      Package_Status,
		muted:       bool,
		strict_only: bool,
		added:       bool,
		held_back:   bool,
	} {
		{.Line_Length, .Strict, false, false, true, false},
		{.Line_Length, .Pending, false, false, true, true},
		{.Line_Length, .Pending, true, false, false, false},
		{.Ignore_Invalid, .Pending, true, false, true, true},
		{.Ignore_Unused, .Pending, false, false, true, true},
		{.Ignore_Unused, .Strict, true, false, false, false},
		{.Import_Escape, .Pending, true, false, true, false},
		{.Path_Case, .Pending, false, false, true, false},
		{.Parse_Unsupported, .Pending, false, false, true, false},
		{.Odin, .Pending, true, false, true, false},
		{.Odin, .Pending, false, true, true, true},
		{.Odin, .Strict, false, true, true, false},
		{.Pending_Stale, .Strict, false, false, true, false},
		{.Format, .Strict, false, false, true, false},
		{.Format, .Pending, false, false, true, true},
		{.Format, .Strict, true, false, false, false},
		{.Name_Case, .Pending, false, false, true, true},
		{.Name_Case, .Strict, true, false, false, false},
		{.Package_Name, .Strict, false, false, true, false},
		{.Package_Name, .Strict, true, false, false, false},
		{.File_Name, .Pending, false, false, true, true},
		{.Import_Alias, .Strict, true, false, false, false},
		{.Import_Order, .Pending, false, false, true, true},
	}
	for c in cases {
		result: Result
		pkg := Package {
			dir    = "lib",
			status = c.status,
			muted  = c.muted,
		}
		add_rule_finding(
			&result,
			&pkg,
			Finding{path = "a.odin", line = 1, col = 1, rule = c.rule},
			c.strict_only,
		)
		added := len(result.findings) == 1
		held_back := added && result.findings[0].held_back
		owned := added && result.findings[0].owner_dir == pkg.dir
		delete(result.findings)
		testing.expectf(
			t,
			added == c.added && held_back == c.held_back && owned == c.added,
			"%v on %v (muted %v, strict only %v): added %v held back %v, want %v %v",
			c.rule,
			c.status,
			c.muted,
			c.strict_only,
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
	add_rule_finding(&result, nil, Finding{path = "/elsewhere/a.odin", rule = .Odin}, true)
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
	add_rule_finding(&result, &pkg, finding, false)
	testing.expect_value(t, len(result.findings), 1)
	if len(result.findings) == 1 {
		testing.expect_value(t, result.findings[0].held_back, true)
		testing.expect_value(t, result.findings[0].owner_dir, "lib")
	}
}

@(test)
rules_table_matches_the_contract_flag_by_flag :: proc(t: ^testing.T) {
	want := [Rule]Rule_Info {
		.Odin                   = {"odin", false, true, .Strict_Only, false},
		.Parse_Unsupported      = {"parse-unsupported", false, true, .No, false},
		.Import_Escape          = {"import-escape", false, true, .No, true},
		.Path_Case              = {"path-case", false, true, .No, true},
		.Line_Length            = {"line-length", true, false, .Yes, false},
		.Ignore_Invalid         = {"ignore-invalid", false, true, .Yes, false},
		.Ignore_Unused          = {"ignore-unused", false, false, .Yes, false},
		.Pending_Stale          = {"pending-stale", false, true, .No, false},
		.Block_Comment          = {"block-comment", false, false, .Yes, true},
		.One_Line_Block         = {"one-line-block", false, false, .Yes, true},
		.Auto_Cast              = {"auto-cast", false, false, .Yes, true},
		.Do_Stmt                = {"do-stmt", false, false, .Yes, true},
		.Fallthrough            = {"fallthrough", true, false, .Yes, true},
		.Bounds_Check_Directive = {"bounds-check-directive", true, false, .Yes, true},
		.Vet_Disabled           = {"vet-disabled", false, false, .Yes, false},
		.Feature_Relaxed        = {"feature-relaxed", true, false, .Yes, false},
		.Transmute              = {"transmute", true, false, .Yes, true},
		.Format                 = {"format", false, false, .Yes, true},
		.Proc_Length            = {"proc-length", true, false, .Yes, true},
		.Nesting_Depth          = {"nesting-depth", true, false, .Yes, true},
		.Name_Case              = {"name-case", true, false, .Yes, true},
		.Package_Name           = {"package-name", false, false, .Yes, false},
		.File_Name              = {"file-name", false, false, .Yes, false},
		.Import_Alias           = {"import-alias", false, false, .Yes, true},
		.Import_Order           = {"import-order", false, false, .Yes, true},
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
		rule:   Rule,
		muted:  bool,
		line:   int,
		hidden: int,
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
			false,
		)
		testing.expectf(
			t,
			pkg.hidden == c.hidden,
			"%v at line %d (muted %v): hidden %d, want %d",
			c.rule,
			c.line,
			c.muted,
			pkg.hidden,
			c.hidden,
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
note_hidden_lists_each_package_with_a_hidden_finding_in_package_order :: proc(t: ^testing.T) {
	packages := []Package {
		{dir = ".", muted = true, hidden = 1},
		{dir = "a", muted = true},
		{dir = "b", muted = true, hidden = 2, status = .Pending},
		{dir = "c"},
	}
	result: Result
	defer delete(result.hidden)
	note_hidden(packages, &result)
	want := []Hidden_Package{{dir = "."}, {dir = "b", held_back = true}}
	testing.expect_value(t, len(result.hidden), len(want))
	for w, i in want {
		if i < len(result.hidden) {
			testing.expect_value(t, result.hidden[i], w)
		}
	}
}

@(test)
note_not_compiled_lists_each_package_a_special_entry_stops_in_package_order :: proc(
	t: ^testing.T,
) {
	packages := []Package {
		{dir = ".", compile = Special_Entry{"lib/x.odin"}},
		{dir = "a", compile = Compiled{{.Darwin_Arm64}}},
		{dir = "b", compile = Special_Entry{"lib/x.odin"}, status = .Pending},
		{dir = "c", compile = Skipped{}},
		{dir = "d", compile = Name_Conflict{}},
		{dir = "lib", compile = Special_Entry{"lib/x.odin"}},
	}
	result: Result
	defer delete(result.not_compiled)
	note_not_compiled(packages, &result)
	want := []Uncompiled_Package {
		{dir = ".", entry = "lib/x.odin"},
		{dir = "b", entry = "lib/x.odin", held_back = true},
		{dir = "lib", entry = "lib/x.odin"},
	}
	testing.expect_value(t, len(result.not_compiled), len(want))
	for w, i in want {
		if i < len(result.not_compiled) {
			testing.expect_value(t, result.not_compiled[i], w)
		}
	}
}
