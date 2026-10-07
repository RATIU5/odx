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
