package odx

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
