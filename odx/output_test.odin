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

	sort_and_dedupe_findings(&findings)

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
sort_prints_exact_duplicates_once_and_drops_held_back_copies_of_shown_findings :: proc(
	t: ^testing.T,
) {
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
		Finding {
			path = "a.odin",
			line = 1,
			col = 1,
			rule = .Odin,
			message = "held",
			held_back = true,
		},
		Finding {
			path = "a.odin",
			line = 1,
			col = 1,
			rule = .Odin,
			message = "held",
			held_back = true,
		},
	)

	sort_and_dedupe_findings(&findings)

	want := []Finding {
		{path = "a.odin", line = 3, col = 4, rule = .Odin, message = "other"},
		dup,
		{path = "a.odin", line = 1, col = 1, rule = .Odin, message = "held", held_back = true},
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
		`{"path":"a/b.odin","line":3,"col":7,"rule":"line-length",` +
		`"message":"line is 120 \"wide\""},` +
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

@(test)
sort_prints_a_finding_once_whichever_packages_it_counts_against :: proc(t: ^testing.T) {
	findings := make([dynamic]Finding)
	defer delete(findings)
	held := Finding {
		path      = "z/z.odin",
		line      = 1,
		col       = 1,
		rule      = .Odin,
		message   = "m",
		held_back = true,
	}
	from_x, from_y := held, held
	from_x.owner_dir = "x"
	from_y.owner_dir = "y"
	append(&findings, from_x, from_y)

	sort_and_dedupe_findings(&findings)

	testing.expect_value(t, len(findings), 1)
}

@(private = "file")
noted_result :: proc() -> Result {
	result := sample_result()
	result.findings[0].note = "odx: format: a/b.odin formatter crashed"
	result.findings[1].note = "odx: format: p/q.odin formatter crashed"
	append(&result.notes, Note{text = "odx: skipped x: no file"})
	return result
}

@(private = "file")
destroy_noted :: proc(result: ^Result) {
	delete(result.findings)
	delete(result.notes)
	delete(result.errors)
}

@(test)
a_note_prints_only_when_its_finding_is_shown :: proc(t: ^testing.T) {
	SHOWN :: "odx: skipped x: no file\nodx: format: a/b.odin formatter crashed\n"
	HELD_BACK :: "odx: format: p/q.odin formatter crashed\n"
	cases := []struct {
		cmd:  Check_Command,
		want: string,
	} {
		{{}, SHOWN},
		{{json = true}, SHOWN},
		{{pending = true}, SHOWN + "odx: pending findings:\n" + HELD_BACK},
		{{json = true, pending = true}, SHOWN + HELD_BACK},
	}
	for c in cases {
		result := noted_result()
		defer destroy_noted(&result)
		w: Written
		defer destroy_written(&w)
		write_to_builders(t, &w, result, c.cmd)
		testing.expectf(
			t,
			strings.to_string(w.err) == c.want,
			"%v: stderr is %q",
			c.cmd,
			strings.to_string(w.err),
		)
	}
}

@(test)
an_error_prints_no_finding_note :: proc(t: ^testing.T) {
	result := noted_result()
	defer destroy_noted(&result)
	append(&result.errors, Error{.Odin_Missing, "no odin"})

	w: Written
	defer destroy_written(&w)
	write_to_builders(t, &w, result, {pending = true})

	testing.expect_value(t, strings.to_string(w.err), "odx: error: odin-missing: no odin\n")
}

@(test)
help_names_every_command_and_exit_code_in_under_20_lines :: proc(t: ^testing.T) {
	wanted := []string {
		"odx check",
		"--json",
		"--pending",
		"odx init",
		"--help",
		"--version",
		"  0  ",
		"  1  ",
		"  2  ",
	}
	for want in wanted {
		testing.expectf(t, strings.contains(HELP, want), "the help text lacks %q", want)
	}
	for unwanted in ([]string{"__format", "odx test", "odx run"}) {
		testing.expectf(t, !strings.contains(HELP, unwanted), "the help text names %q", unwanted)
	}
	testing.expect(t, strings.has_suffix(HELP, "\n"), "the help text must end its last line")
	testing.expect(t, strings.count(HELP, "\n") < 20, "the help text must stay under 20 lines")
}

@(test)
version_line_names_the_release_the_rule_set_and_the_compiler :: proc(t: ^testing.T) {
	line := version_line(context.allocator)
	defer delete(line)
	testing.expect_value(t, line, "odx 0.1.0, rule set 1, odin dev-2026-09-nightly:a2fb372\n")
}

HIDDEN_ROOT_LINE :: "odx: .: compile errors hide this package's other findings\n"
HIDDEN_LIB_LINE :: "odx: lib: compile errors hide this package's other findings\n"

hidden_result :: proc() -> Result {
	result := sample_result()
	append(
		&result.notes,
		Note{text = "odx: skipped t: no file"},
		Note{text = "odx: .: compile errors hide this package's other findings"},
		Note{"odx: lib: compile errors hide this package's other findings", true},
	)
	result.findings[0].note = "odx: format: a/b.odin formatter crashed"
	return result
}

destroy_hidden_result :: proc(result: ^Result) {
	delete(result.findings)
	delete(result.notes)
}

@(test)
hidden_lines_follow_the_notes_and_leave_stdout_alone :: proc(t: ^testing.T) {
	result := hidden_result()
	defer destroy_hidden_result(&result)
	plain := sample_result()
	defer delete(plain.findings)

	for cmd in ([]Check_Command{{}, {json = true}}) {
		w, without: Written
		defer destroy_written(&w)
		defer destroy_written(&without)
		write_to_builders(t, &w, result, cmd)
		write_to_builders(t, &without, plain, cmd)
		testing.expect_value(t, strings.to_string(w.out), strings.to_string(without.out))
		testing.expect_value(
			t,
			strings.to_string(w.err),
			"odx: skipped t: no file\n" +
			HIDDEN_ROOT_LINE +
			"odx: format: a/b.odin formatter crashed\n",
		)
	}
}

@(test)
hidden_line_of_a_pending_package_needs_the_pending_flag :: proc(t: ^testing.T) {
	result := hidden_result()
	defer destroy_hidden_result(&result)

	for cmd in ([]Check_Command{{pending = true}, {pending = true, json = true}}) {
		w: Written
		defer destroy_written(&w)
		write_to_builders(t, &w, result, cmd)
		got := strings.to_string(w.err)
		testing.expectf(
			t,
			strings.contains(got, HIDDEN_ROOT_LINE + HIDDEN_LIB_LINE),
			"json %v: stderr is %q",
			cmd.json,
			got,
		)
	}
}

@(test)
test_tagged_and_retry_lines_print_between_the_package_lines_and_the_finding_notes :: proc(
	t: ^testing.T,
) {
	result := hidden_result()
	defer destroy_hidden_result(&result)
	inject_at(
		&result.notes,
		1,
		Note{text = "odx: app: the compiler doesn't check 2 files tagged #+test"},
		Note{"odx: old: the compiler doesn't check 1 files tagged #+test", true},
	)
	result.compiler_retries = 3
	plain := sample_result()
	defer delete(plain.findings)
	APP :: "odx: app: the compiler doesn't check 2 files tagged #+test\n"
	OLD :: "odx: old: the compiler doesn't check 1 files tagged #+test\n"
	RETRIES :: "odx: the compiler died by a signal 3 times, and odx ran it again each time\n"
	BEFORE :: "odx: skipped t: no file\n"
	NOTE :: "odx: format: a/b.odin formatter crashed\n"

	for json in ([]bool{false, true}) {
		w, pending, without: Written
		defer destroy_written(&w)
		defer destroy_written(&pending)
		defer destroy_written(&without)
		write_to_builders(t, &w, result, {json = json})
		write_to_builders(t, &pending, result, {json = json, pending = true})
		write_to_builders(t, &without, plain, {json = json})
		testing.expect_value(t, strings.to_string(w.out), strings.to_string(without.out))
		testing.expect_value(
			t,
			strings.to_string(w.err),
			BEFORE + APP + HIDDEN_ROOT_LINE + RETRIES + NOTE,
		)
		got := strings.to_string(pending.err)
		testing.expectf(
			t,
			strings.has_prefix(
				got,
				BEFORE + APP + OLD + HIDDEN_ROOT_LINE + HIDDEN_LIB_LINE + RETRIES + NOTE,
			),
			"json %v: stderr is %q",
			json,
			got,
		)
	}

	result.compiler_retries = 0
	none: Written
	defer destroy_written(&none)
	write_to_builders(t, &none, result, {})
	testing.expect_value(t, strings.to_string(none.err), BEFORE + APP + HIDDEN_ROOT_LINE + NOTE)

	// An error leaves the retry line as the only other stderr line, after the errors.
	result.compiler_retries = 3
	append(&result.errors, Error{.Compiler_Output, "first"}, Error{.Config_Invalid, "bad"})
	defer delete(result.errors)
	ERRORS :: "odx: error: compiler-output: first\nodx: error: config-invalid: bad\n"
	for json in ([]bool{false, true}) {
		failed, quiet: Written
		defer destroy_written(&failed)
		defer destroy_written(&quiet)
		write_to_builders(t, &failed, result, {json = json, pending = true})
		testing.expect_value(t, strings.to_string(failed.err), ERRORS + RETRIES)
		testing.expect(
			t,
			!strings.contains(strings.to_string(failed.out), "died by a signal"),
			"the retry line is on stdout",
		)
		no_retries := result
		no_retries.compiler_retries = 0
		write_to_builders(t, &quiet, no_retries, {json = json, pending = true})
		testing.expect_value(t, strings.to_string(quiet.err), ERRORS)
		testing.expect_value(t, strings.to_string(failed.out), strings.to_string(quiet.out))
	}
}

@(test)
hidden_lines_are_not_written_with_an_error :: proc(t: ^testing.T) {
	result := hidden_result()
	defer destroy_hidden_result(&result)
	append(&result.errors, Error{.Config_Invalid, "bad"})
	defer delete(result.errors)

	w: Written
	defer destroy_written(&w)
	write_to_builders(t, &w, result, {pending = true})
	testing.expect_value(t, strings.to_string(w.err), "odx: error: config-invalid: bad\n")
}
