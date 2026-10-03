package odx

import "core:strings"
import "core:testing"

@(test)
sort_orders_by_path_line_col_rule_message_then_held_back :: proc(t: ^testing.T) {
	findings := make([dynamic]Finding)
	defer delete(findings)
	append(
		&findings,
		Finding{path = "b.odin", line = 1, col = 1, rule = .Odin, message = "m"},
		Finding{path = "a.odin", line = 1, col = 1, rule = .Odin, message = "m", held_back = true},
		Finding{path = "a.odin", line = 10, col = 1, rule = .Odin, message = "m"},
		Finding{path = "a.odin", line = 9, col = 2, rule = .Odin, message = "m"},
		Finding{path = "a.odin", line = 9, col = 1, rule = .Odin, message = "z"},
		Finding{path = "a.odin", line = 9, col = 1, rule = .Odin, message = "a"},
		Finding{path = "a.odin", line = 9, col = 1, rule = .Line_Length, message = "z"},
	)

	sort_findings(&findings)

	want := []Finding {
		{path = "a.odin", line = 9, col = 1, rule = .Line_Length, message = "z"},
		{path = "a.odin", line = 9, col = 1, rule = .Odin, message = "a"},
		{path = "a.odin", line = 9, col = 1, rule = .Odin, message = "z"},
		{path = "a.odin", line = 9, col = 2, rule = .Odin, message = "m"},
		{path = "a.odin", line = 10, col = 1, rule = .Odin, message = "m"},
		{path = "b.odin", line = 1, col = 1, rule = .Odin, message = "m"},
		{path = "a.odin", line = 1, col = 1, rule = .Odin, message = "m", held_back = true},
	}
	testing.expect_value(t, len(findings), len(want))
	for w, i in want {
		if i >= len(findings) {
			break
		}
		testing.expectf(t, findings[i] == w, "findings[%d] = %v, want %v", i, findings[i], w)
	}
}

@(test)
sort_prints_exact_duplicates_once :: proc(t: ^testing.T) {
	findings := make([dynamic]Finding)
	defer delete(findings)
	dup := Finding {
		path    = "a.odin",
		line    = 3,
		col     = 4,
		rule    = .Odin,
		message = "same",
	}
	append(
		&findings,
		dup,
		Finding{path = "a.odin", line = 3, col = 4, rule = .Odin, message = "other"},
		dup,
		dup,
		Finding {
			path = "a.odin",
			line = 3,
			col = 4,
			rule = .Odin,
			message = "same",
			held_back = true,
		},
	)

	sort_findings(&findings)

	want := []Finding {
		{path = "a.odin", line = 3, col = 4, rule = .Odin, message = "other"},
		dup,
		{path = "a.odin", line = 3, col = 4, rule = .Odin, message = "same", held_back = true},
	}
	testing.expect_value(t, len(findings), len(want))
	for w, i in want {
		if i >= len(findings) {
			break
		}
		testing.expectf(t, findings[i] == w, "findings[%d] = %v, want %v", i, findings[i], w)
	}
}

@(test)
exit_code_is_2_on_error_even_with_findings :: proc(t: ^testing.T) {
	finding := Finding {
		path    = "a.odin",
		line    = 1,
		col     = 1,
		rule    = .Odin,
		message = "m",
	}
	held := Finding {
		path      = "a.odin",
		line      = 1,
		col       = 1,
		rule      = .Odin,
		message   = "m",
		held_back = true,
	}
	err := Error{.Odin_Missing, "m"}

	cases := []struct {
		name:     string,
		findings: []Finding,
		errors:   []Error,
		want:     int,
	} {
		{"clean", {}, {}, 0},
		{"held back only", {held}, {}, 0},
		{"findings", {finding}, {}, 1},
		{"error", {}, {err}, 2},
		{"error and findings", {finding, held}, {err}, 2},
	}
	for c in cases {
		result: Result
		append(&result.findings, ..c.findings)
		append(&result.errors, ..c.errors)
		got := exit_code(result)
		delete(result.findings)
		delete(result.errors)
		testing.expectf(t, got == c.want, "%s: exit %d, want %d", c.name, got, c.want)
	}
}

Written :: struct {
	out: strings.Builder,
	err: strings.Builder,
}

write_to_builders :: proc(t: ^testing.T, w: ^Written, result: Result, cmd: Check_Command) {
	strings.builder_init(&w.out)
	strings.builder_init(&w.err)
	io_err := write_result(strings.to_writer(&w.out), strings.to_writer(&w.err), result, cmd)
	testing.expect_value(t, io_err, nil)
}

destroy_written :: proc(w: ^Written) {
	strings.builder_destroy(&w.out)
	strings.builder_destroy(&w.err)
}

sample_result :: proc() -> Result {
	result := Result {
		ignored  = 2,
		pending  = 1,
		skipped  = 3,
		rule_set = 1,
		odin     = "dev-x",
	}
	append(
		&result.findings,
		Finding {
			path = "a/b.odin",
			line = 3,
			col = 7,
			rule = .Line_Length,
			message = `line is 120 "wide"`,
		},
		Finding {
			path = "p/q.odin",
			line = 1,
			col = 1,
			rule = .Odin,
			message = "held",
			held_back = true,
		},
	)
	return result
}

@(test)
text_prints_findings_then_summary :: proc(t: ^testing.T) {
	result := sample_result()
	defer delete(result.findings)

	w: Written
	defer destroy_written(&w)
	write_to_builders(t, &w, result, {})

	testing.expect_value(
		t,
		strings.to_string(w.out),
		"a/b.odin:3:7: line-length: line is 120 \"wide\"\n" +
		"odx: 1 findings, 2 ignored, 1 pending, 3 skipped (rules 1, odx " +
		RELEASE +
		", odin dev-x)\n",
	)
	testing.expect_value(t, strings.to_string(w.err), "")
}

@(test)
text_prints_held_back_findings_only_with_pending :: proc(t: ^testing.T) {
	result := sample_result()
	defer delete(result.findings)

	w: Written
	defer destroy_written(&w)
	write_to_builders(t, &w, result, {pending = true})

	testing.expect_value(
		t,
		strings.to_string(w.out),
		"a/b.odin:3:7: line-length: line is 120 \"wide\"\n" +
		"p/q.odin:1:1: odin: held\n" +
		"odx: 1 findings, 2 ignored, 1 pending, 3 skipped (rules 1, odx " +
		RELEASE +
		", odin dev-x)\n",
	)
	testing.expect_value(t, strings.to_string(w.err), "odx: pending findings:\n")
}

@(test)
text_error_prints_no_result :: proc(t: ^testing.T) {
	result := sample_result()
	defer delete(result.findings)
	append(&result.errors, Error{.Odin_Missing, "no odin"})
	defer delete(result.errors)

	w: Written
	defer destroy_written(&w)
	write_to_builders(t, &w, result, {})

	testing.expect_value(t, strings.to_string(w.out), "")
	testing.expect_value(t, strings.to_string(w.err), "odx: error: odin-missing: no odin\n")
}

@(test)
json_prints_one_document :: proc(t: ^testing.T) {
	result := sample_result()
	defer delete(result.findings)

	w: Written
	defer destroy_written(&w)
	write_to_builders(t, &w, result, {json = true, pending = true})

	testing.expect_value(
		t,
		strings.to_string(w.out),
		`{"version":1,"findings":[` +
		`{"path":"a/b.odin","line":3,"col":7,"rule":"line-length","message":"line is 120 \"wide\""},` +
		`{"path":"p/q.odin","line":1,"col":1,"rule":"odin","message":"held","pending":true}],` +
		`"errors":[],` +
		`"summary":{"findings":1,"ignored":2,"pending":1,"skipped":3,"rules":1,"release":"` +
		RELEASE +
		`","odin":"dev-x"}}` +
		"\n",
	)
	testing.expect_value(t, strings.to_string(w.err), "")
}

@(test)
json_error_has_no_findings :: proc(t: ^testing.T) {
	result := sample_result()
	defer delete(result.findings)
	append(&result.errors, Error{.Odin_Missing, "no odin"})
	defer delete(result.errors)

	w: Written
	defer destroy_written(&w)
	write_to_builders(t, &w, result, {json = true})

	testing.expect_value(
		t,
		strings.to_string(w.out),
		`{"version":1,"findings":[],` +
		`"errors":[{"code":"odin-missing","message":"no odin"}],` +
		`"summary":{"findings":0,"ignored":0,"pending":0,"skipped":0,"rules":1,"release":"` +
		RELEASE +
		`","odin":"dev-x"}}` +
		"\n",
	)
	testing.expect_value(t, strings.to_string(w.err), "odx: error: odin-missing: no odin\n")
}

@(test)
json_escapes_control_characters :: proc(t: ^testing.T) {
	result := Result {
		rule_set = 1,
		odin     = "dev-x",
	}
	append(
		&result.findings,
		Finding{path = `a\b.odin`, line = 1, col = 1, rule = .Odin, message = "tab\tnl\nbell\x01"},
	)
	defer delete(result.findings)

	w: Written
	defer destroy_written(&w)
	write_to_builders(t, &w, result, {json = true})

	testing.expect(
		t,
		strings.contains(
			strings.to_string(w.out),
			`{"path":"a\\b.odin","line":1,"col":1,"rule":"odin","message":"tab\tnl\nbell\u0001"}`,
		),
		strings.to_string(w.out),
	)
}
