package odx

import "core:fmt"
import "core:slice"
import "core:strings"

Severity :: enum {
	error, // the zero value: every finding is an error unless a rule says otherwise
	warning,
}

Violation :: struct {
	file:          string, // relative to root
	line:          int,
	col:           int,
	rule:          string, // "topic/R3", "odin/error", "odx/bad-ignore"
	severity:      Severity,
	check:         string,
	message:       string,
	ignorable:     bool,
	class:         string, // stable greppable name from the rule's frontmatter; "" for odin/odx findings
	statement:     string, // the rule's statement and why, so a block message is self-sufficient
	why:           string,
	subject:       string, // rule-provided semantic label; baseline identity also binds source and position
	baselined:     bool, // listed in odx.baseline: printed, never fails the build
	blocking:      bool, // reserved schema-1 compatibility value; not the exit-status decision
	fires:         string, // the rule's compiled violating and correct forms, "" for notes
	silent:        string,
	// the agent contract: what to write instead, and the exact suppression line, so a
	// consumer can act on one finding without a second call; "" for notes
	fix_hint:      string,
	instead_of:    string,
	evidence:      string,
	boundary:      string,
	ignore_syntax: string,
}

// ignore_syntax_of: the comment that suppresses rule at file; package-level findings (file is a
// directory) take the -file form on line 1-3 of any file in it.
ignore_syntax_of :: proc(file, rule: string) -> string {
	if strings.has_suffix(file, ".odin") {
		return fmt.tprintf("// %s %s reason: <at least ten characters>", IGNORE_PREFIX, rule)
	}
	return fmt.tprintf("// %s %s reason: <at least ten characters>", IGNORE_FILE_PREFIX, rule)
}

Report :: struct {
	schema:      int,
	coverage:    Coverage,
	violations:  [dynamic]Violation,
	tool_errors: [dynamic]string,
	summary:     struct {
		errors, warnings, ignored, files, omitted, baselined: int,
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
			blocking = true,
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
		if a.rule != b.rule {return a.rule < b.rule}
		if a.subject != b.subject {return a.subject < b.subject}
		return a.message < b.message
	})
}

finalize :: proc(r: ^Report, strict: bool, max_violations := 0) -> int {
	r.schema = 1
	sort_violations(r.violations[:])
	for v in r.violations {
		if v.baselined {
			r.summary.baselined += 1
			continue
		}
		switch v.severity {
		case .error:
			r.summary.errors += 1
		case .warning:
			r.summary.warnings += 1
		}
	}
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
	fmt.print(coverage_text(r))
	print_tool_errors(r)
	if len(r.violations) == 0 && len(r.tool_errors) == 0 && r.coverage.complete {
		fmt.printfln("ok: %d files, %d ignored", r.summary.files, r.summary.ignored)
	} else if len(r.violations) == 0 && len(r.tool_errors) == 0 {
		fmt.printfln(
			"no findings in completed checks: %d files, %d ignored",
			r.summary.files,
			r.summary.ignored,
		)
	}
}

print_tool_errors :: proc(r: ^Report) {
	for e in r.tool_errors {fmt.eprintln("odx: tool error:", e)}
}

BASELINED_TAG :: " [baselined]"

report_text :: proc(r: ^Report) -> string {
	b := strings.builder_make()
	for v in r.violations {
		topic, _, rule := strings.partition(v.rule, "/")
		hint :=
			"" if topic == "odin" || topic == "odx" else fmt.tprintf("; see `odx explain %s --rule %s`", topic, rule)
		fmt.sbprintfln(
			&b,
			"%s:%d:%d: %s %s%s%s",
			v.file,
			v.line,
			v.col,
			v.rule,
			v.message,
			hint,
			BASELINED_TAG if v.baselined else "",
		)
		if v.fix_hint != "" {fmt.sbprintfln(&b, "  repair: %s", v.fix_hint)}
		if v.why != "" {fmt.sbprintfln(&b, "  why: %s", v.why)}
		if v.boundary != "" {fmt.sbprintfln(&b, "  evidence: %s; %s", v.evidence, v.boundary)}
	}
	if r.summary.omitted >
	   0 {fmt.sbprintfln(&b, "... %d more violations omitted (--max-violations)", r.summary.omitted)}
	return strings.to_string(b)
}

// hook_text is report_text for the model: the first violation of each rule carries the
// statement, the why, and the exact escape hatch (only when the rule takes one); later ones are
// bare location lines. Compiler findings never have a body.
hook_text :: proc(r: ^Report) -> string {
	b := strings.builder_make()
	seen := make(map[string]bool, context.temp_allocator)
	for v in r.violations {
		fmt.sbprintfln(
			&b,
			"%s:%d:%d: %s %s%s",
			v.file,
			v.line,
			v.col,
			v.rule,
			v.message,
			BASELINED_TAG if v.baselined else "",
		)
		if v.statement == "" || v.rule in seen || v.baselined {continue}
		seen[v.rule] = true
		fmt.sbprintfln(&b, "  rule: %s\n  why: %s", v.statement, v.why)
		if v.fix_hint != "" {fmt.sbprintfln(&b, "  repair: %s", v.fix_hint)}
		if v.boundary != "" {fmt.sbprintfln(&b, "  evidence: %s; %s", v.evidence, v.boundary)}
		if v.fires != "" {fmt.sbprintfln(&b, "  violates, like this:\n%s", indent(v.fires))}
		if v.silent != "" {fmt.sbprintfln(&b, "  passes, like this:\n%s", indent(v.silent))}
		if v.ignorable {
			if strings.has_suffix(v.file, ".odin") {
				fmt.sbprintfln(
					&b,
					"  to suppress, on the line above it: %s",
					ignore_syntax_of(v.file, v.rule),
				)
			} else {
				fmt.sbprintfln(
					&b,
					"  to suppress, on line 1-3 of any file in %s/: %s",
					v.file,
					ignore_syntax_of(v.file, v.rule),
				)
			}
		}
	}
	if r.summary.omitted >
	   0 {fmt.sbprintfln(&b, "... %d more violations omitted (--max-violations)", r.summary.omitted)}
	return strings.to_string(b)
}
