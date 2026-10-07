package odx

import "core:testing"

@(test)
has_case_follows_the_three_case_definitions :: proc(t: ^testing.T) {
	cases := []struct {
		name: string,
		has:  bit_set[Case],
	} {
		{"JSON_Value", {.Ada}},
		{"Http_Client", {.Ada}},
		{"Vec2", {.Ada}},
		{"T", {.Ada, .Screaming}},
		{"ID", {.Ada, .Screaming}},
		{"X1", {.Ada, .Screaming}},
		{"MAX_4K", {.Ada, .Screaming}},
		{"HttpClient", {}},
		{"Vec2D", {}},
		{"Json_value", {}},
		{"Matrix_4x4", {.Ada}},
		{"Matrix_4X4", {.Ada}},
		{"Matrix_4X4x", {}},
		{"Matrix_4", {.Ada}},
		{"MATRIX_4x4", {.Ada}},
		{"vec_2d", {.Snake}},
		{"x", {.Snake}},
		{"x1", {.Snake}},
		{"max_size", {.Snake}},
		{"maxSize", {}},
		{"Max_size", {}},
		{"2d", {}},
		{"4K", {}},
		{"_x", {}},
		{"_X", {}},
		{"a__b", {}},
		{"A__B", {}},
		{"x_", {}},
		{"X_", {}},
		{"héllo", {}},
		{"Größe", {}},
		{"_", {}},
		{"", {}},
		{"a-b", {}},
		{"a.b", {}},
	}
	for c in cases {
		for want in Case {
			testing.expectf(
				t,
				has_case(c.name, want) == (want in c.has),
				"has_case(%q, %v) is %v",
				c.name,
				want,
				has_case(c.name, want),
			)
		}
	}
}

@(test)
name_cases_table_matches_the_contract_kind_by_kind :: proc(t: ^testing.T) {
	want := [Name_Kind]Case {
		.Type                 = .Ada,
		.Enum_Member          = .Ada,
		.Poly_Type            = .Ada,
		.Proc                 = .Snake,
		.Proc_Group           = .Snake,
		.Value_Constant       = .Screaming,
		.Poly_Value           = .Screaming,
		.Package_Literal      = .Screaming,
		.Variable             = .Snake,
		.Parameter            = .Snake,
		.Result               = .Snake,
		.Field                = .Snake,
		.Label                = .Snake,
		.Loop_Variable        = .Snake,
		.Type_Switch_Variable = .Snake,
		.Import_Alias         = .Snake,
		.Foreign_Import       = .Snake,
	}
	for got, kind in NAME_CASES {
		testing.expectf(t, got == want[kind], "%v: %v, want %v", kind, got, want[kind])
	}
}

@(test)
import_group_reads_the_path_prefix :: proc(t: ^testing.T) {
	cases := []struct {
		path: string,
		want: Import_Group,
	} {
		{"base:runtime", .Base_Core},
		{"core:fmt", .Base_Core},
		{"core:compress/gzip", .Base_Core},
		{"vendor:zlib", .Vendor},
		{"libs:util", .Collection},
		{"shared:foo", .Collection},
		{"corelib:x", .Collection},
		{"../lib", .Relative},
		{"lib", .Relative},
		{"./core", .Relative},
	}
	for c in cases {
		testing.expectf(
			t,
			import_group(c.path) == c.want,
			"import_group(%q) is %v, want %v",
			c.path,
			import_group(c.path),
			c.want,
		)
	}
}

@(test)
import_step_judges_order_before_spacing :: proc(t: ^testing.T) {
	cases := []struct {
		name:          string,
		prev, next:    Import_Group,
		blanks, other: int,
		want:          Import_Break,
	} {
		{"one group, adjacent", .Base_Core, .Base_Core, 0, 0, .None},
		{"one group, a blank line", .Vendor, .Vendor, 1, 0, .Group_Split},
		{"one group, a comment line", .Relative, .Relative, 0, 1, .Group_Split},
		{"next group, one blank line", .Base_Core, .Vendor, 1, 0, .None},
		{"a group skipped, one blank line", .Base_Core, .Relative, 1, 0, .None},
		{"next group, adjacent", .Base_Core, .Vendor, 0, 0, .Groups_Not_Separated},
		{"next group, two blank lines", .Vendor, .Collection, 2, 0, .Groups_Not_Separated},
		{"next group, a blank and a comment", .Vendor, .Relative, 1, 1, .Groups_Not_Separated},
		{"earlier group, one blank line", .Vendor, .Base_Core, 1, 0, .Out_Of_Order},
		{"earlier group, adjacent", .Relative, .Collection, 0, 0, .Out_Of_Order},
	}
	for c in cases {
		got := import_step(c.prev, c.next, c.blanks, c.other)
		testing.expectf(t, got == c.want, "%s: %v, want %v", c.name, got, c.want)
	}
}

@(test)
unaliased_import_name_is_the_last_path_component :: proc(t: ^testing.T) {
	cases := [][2]string {
		{"core:fmt", "fmt"},
		{"core:compress/gzip", "gzip"},
		{"../lib", "lib"},
		{"lib", "lib"},
		{"libs:util", "util"},
		{"vendor:stb/image", "image"},
	}
	for c in cases {
		testing.expectf(
			t,
			unaliased_import_name(c[0]) == c[1],
			"unaliased_import_name(%q) is %q, want %q",
			c[0],
			unaliased_import_name(c[0]),
			c[1],
		)
	}
}
