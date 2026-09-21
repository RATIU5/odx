package odx

import "core:strings"
import "core:testing"

// The block message must be self-sufficient (M2.2): body once per rule, hatch only if ignorable.
@(test)
test_hook_text_dedups_by_rule :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	r: Report
	v := Violation {
		file      = "a.odin",
		line      = 1,
		col       = 1,
		rule      = "x/R1",
		message   = "m",
		statement = "S",
		why       = "W",
		ignorable = true,
	}
	append(&r.violations, v)
	v.line = 2
	append(&r.violations, v)
	append(
		&r.violations,
		Violation {
			file = "a.odin",
			line = 3,
			col = 1,
			rule = "y/R1",
			message = "n",
			statement = "T",
			why = "V",
		},
	)
	out := hook_text(&r)
	testing.expect_value(t, strings.count(out, "rule: S"), 1)
	testing.expect_value(t, strings.count(out, "a.odin:"), 3)
	testing.expect_value(t, strings.count(out, "to suppress"), 1) // y/R1 is not ignorable
	testing.expect(t, strings.contains(out, "// odx:ignore x/R1 reason:"))
}

// The output contract (M10.2): baselined findings never count, truncation is reported.
@(test)
test_finalize_counts_and_omitted :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	r: Report
	for i in 1 ..= 4 {
		append(&r.violations, Violation{file = "a.odin", line = i, rule = "x/R1", baselined = i == 1})
	}
	code := finalize(&r, false, 2)
	testing.expect_value(t, code, EXIT_VIOLATION)
	testing.expect_value(t, r.summary.errors, 3)
	testing.expect_value(t, r.summary.baselined, 1)
	testing.expect_value(t, r.summary.omitted, 2)
	testing.expect_value(t, len(r.violations), 2)
	testing.expect(t, strings.contains(report_text(&r), "2 more violations omitted"))
	only_base: Report
	append(&only_base.violations, Violation{rule = "x/R1", baselined = true})
	testing.expect_value(t, finalize(&only_base, true), 0)
}
