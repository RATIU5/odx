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
