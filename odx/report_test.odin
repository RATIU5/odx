package odx

import "core:strings"
import "core:testing"

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

@(test)
test_finalize_counts_and_omitted :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	r: Report
	for i in 1 ..= 4 {
		append(
			&r.violations,
			Violation{file = "a.odin", line = i, rule = "x/R1", baselined = i == 1},
		)
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

@(test)
test_warning_exit_contract :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	for strict in ([]bool{false, true}) {
		for baselined in ([]bool{false, true}) {
			for complete in ([]bool{false, true}) {
				r: Report
				r.coverage.complete = complete
				append(
					&r.violations,
					Violation{severity = .warning, baselined = baselined, blocking = true},
				)
				code := finalize(&r, strict)
				testing.expect_value(t, code, EXIT_VIOLATION if strict && !baselined else 0)
				testing.expect_value(t, r.schema, 1)
				testing.expect_value(t, r.summary.warnings, 0 if baselined else 1)
				testing.expect_value(t, r.summary.baselined, 1 if baselined else 0)
				testing.expect_value(t, r.coverage.complete, complete)
				testing.expect(t, r.violations[0].blocking)
			}
		}
	}
	r: Report
	append(&r.violations, Violation{severity = .warning})
	tool_error(&r, "required graph evidence unavailable")
	testing.expect_value(t, finalize(&r, true), EXIT_TOOL)
}

@(test)
test_repair_metadata_and_order :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	r := Rule {
		statement = "No mutable globals.",
		why = "State belongs to the caller.",
		instead_of = "Mutable global state.",
		fix_hint = "Pass state as a parameter.",
		check = {kind = .pattern, match = "decl", at = "package_scope", mutable = true},
	}
	a := Active_Rule{"local/R1", &r}
	c := Ctx {
		r = new(Report),
	}
	report(&c, &a, "lib/a.odin", 2, 1, "second", "z")
	report(&c, &a, "lib/a.odin", 2, 1, "second", "a")
	report(&c, &a, "lib/a.odin", 2, 1, "first", "a")
	sort_violations(c.r.violations[:])
	v := c.r.violations[0]
	testing.expect_value(t, v.subject, "a")
	testing.expect_value(t, v.message, "first")
	testing.expect_value(t, c.r.violations[2].subject, "z")
	testing.expect_value(t, v.fix_hint, "Pass state as a parameter.")
	testing.expect_value(t, v.instead_of, "Mutable global state.")
	evidence, boundary := rule_evidence(r.check)
	testing.expect_value(t, v.evidence, evidence)
	testing.expect_value(t, v.boundary, boundary)
	testing.expect(t, strings.contains(report_text(c.r), "repair: Pass state as a parameter."))
	testing.expect(t, strings.contains(hook_text(c.r), "evidence: native_ast;"))
	testing.expect_value(t, strings.count(hook_text(c.r), "repair:"), 1)
	r.fix_hint = ""
	testing.expect_value(t, rule_fix_hint(&r), r.statement)
}
