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
	statement: string, // the rule's statement and why (M2.2), so a block message is self-sufficient
	why:       string,
	subject:   string, // stable semantic key (M3.1); "" = not baselineable
	baselined: bool, // listed in odx.baseline: printed, never fails the build
	blocking:  bool, // P4: the hook may block on it; notes (odin/*, odx/*) always are
}

Report :: struct {
	schema:      int,
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
		return a.rule < b.rule
	})
}

// finalize sorts, tallies and returns the exit code (17.11).
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

BASELINED_TAG :: " [baselined]"

// report_text: one line per violation, the human format (17.11).
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
	}
	if r.summary.omitted >
	   0 {fmt.sbprintfln(&b, "... %d more violations omitted (--max-violations)", r.summary.omitted)}
	return strings.to_string(b)
}

// hook_blocks: does this report contain anything the hook should wall on (P4)? Advisory
// rules and baselined findings are printed but never block.
hook_blocks :: proc(r: ^Report) -> bool {
	if len(r.tool_errors) > 0 {return true}
	for v in r.violations {if v.blocking && !v.baselined {return true}}
	return false
}

// hook_text is report_text for the model (M2.2): the first violation of each rule carries the
// statement, the why, and the exact escape hatch (only when the rule takes one); later ones are
// bare location lines. Compiler findings never have a body. M8 adds fires/silent here.
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
		if v.ignorable {
			if strings.has_suffix(v.file, ".odin") {
				fmt.sbprintfln(
					&b,
					"  to suppress, on the line above it: // %s %s reason: <at least ten characters>",
					IGNORE_PREFIX,
					v.rule,
				)
			} else {
				fmt.sbprintfln(
					&b,
					"  to suppress, on line 1-3 of any file in %s/: // %s %s reason: <at least ten characters>",
					v.file,
					IGNORE_FILE_PREFIX,
					v.rule,
				)
			}
		}
	}
	if r.summary.omitted >
	   0 {fmt.sbprintfln(&b, "... %d more violations omitted (--max-violations)", r.summary.omitted)}
	return strings.to_string(b)
}
