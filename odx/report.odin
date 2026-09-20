package odx

import "core:fmt"
import "core:slice"
import "core:strings"

Severity :: enum {
	error, // the zero value: every finding is an error unless a rule says otherwise
	warning,
}

// Violation is the one output record (17.11).
Violation :: struct {
	file:      string, // relative to root
	line:      int,
	col:       int,
	rule:      string, // "topic/R3", "odin/error", "odx/bad-ignore"
	severity:  Severity,
	check:     string, // the check kind or family that produced it
	message:   string,
	ignorable: bool,
	class:     string, // stable greppable name from the rule's frontmatter (20.4); "" for odin/odx findings
}

Report :: struct {
	schema:      int,
	violations:  [dynamic]Violation,
	tool_errors: [dynamic]string,
	summary:     struct {
		errors, warnings, ignored, files, omitted: int,
	},
}

// note records an odin/* or odx/* finding: never ignorable, no rule class.
note :: proc(r: ^Report, rule, check, file: string, line, col: int, message: string) {
	append(
		&r.violations,
		Violation {
			file = file,
			line = line,
			col = col,
			rule = rule,
			check = check,
			message = message,
		},
	)
}

tool_error :: proc(r: ^Report, f: string, args: ..any) {
	append(&r.tool_errors, fmt.aprintf(f, ..args))
}

sort_violations :: proc(vs: []Violation) {
	slice.sort_by(vs, proc(a, b: Violation) -> bool {
		if a.file != b.file {return a.file < b.file}
		if a.line != b.line {return a.line < b.line}
		if a.col != b.col {return a.col < b.col}
		return a.rule < b.rule
	})
}

// finalize sorts, tallies and returns the exit code (17.11).
finalize :: proc(r: ^Report, strict: bool, max_violations := 0) -> int {
	r.schema = 1
	sort_violations(r.violations[:])
	for v in r.violations {
		switch v.severity {
		case .error:
			r.summary.errors += 1
		case .warning:
			r.summary.warnings += 1
		}
	}
	// truncation is reported, never silent (20.8)
	if max_violations > 0 && len(r.violations) > max_violations {
		r.summary.omitted = len(r.violations) - max_violations
		resize(&r.violations, max_violations)
	}
	if len(r.tool_errors) > 0 {return EXIT_TOOL}
	if r.summary.errors > 0 || (strict && r.summary.warnings > 0) {return EXIT_VIOLATION}
	return 0
}

print_report :: proc(r: ^Report, json_out: bool) {
	if json_out {
		print_json(r^)
		return
	}
	fmt.print(report_text(r))
	print_tool_errors(r)
	if len(r.violations) == 0 && len(r.tool_errors) == 0 {
		fmt.printfln("ok: %d files, %d ignored", r.summary.files, r.summary.ignored)
	}
}

print_tool_errors :: proc(r: ^Report) {
	for e in r.tool_errors {fmt.eprintln("odx: tool error:", e)}
}

// report_text: one line per violation, the human format (17.11).
report_text :: proc(r: ^Report) -> string {
	b := strings.builder_make()
	for v in r.violations {
		topic, _, rule := strings.partition(v.rule, "/")
		hint :=
			"" if topic == "odin" || topic == "odx" else fmt.tprintf("; see `odx explain %s --rule %s`", topic, rule)
		fmt.sbprintfln(&b, "%s:%d:%d: %s %s%s", v.file, v.line, v.col, v.rule, v.message, hint)
	}
	if r.summary.omitted >
	   0 {fmt.sbprintfln(&b, "... %d more violations omitted (--max-violations)", r.summary.omitted)}
	return strings.to_string(b)
}
