package odx

import "core:fmt"
import "core:slice"
import "core:strings"

// Violation is the one output record (17.11).
Violation :: struct {
	file:      string, // relative to root
	line:      int,
	col:       int,
	rule:      string, // "topic/R3", "odin/error", "odx/bad-ignore"
	severity:  string, // "error" | "warning"
	check:     string,
	message:   string,
	ignorable: bool,
}

Report :: struct {
	schema:      int,
	violations:  [dynamic]Violation,
	tool_errors: [dynamic]string,
	summary:     struct {
		errors, warnings, ignored, files: int,
	},
}

add :: proc(r: ^Report, v: Violation) {
	v := v
	if v.severity == "" {v.severity = "error"}
	append(&r.violations, v)
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
finalize :: proc(r: ^Report, strict: bool) -> int {
	r.schema = 1
	sort_violations(r.violations[:])
	for v in r.violations {
		if v.severity == "warning" {r.summary.warnings += 1} else {r.summary.errors += 1}
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
	for v in r.violations {
		topic, _, rule := strings.partition(v.rule, "/")
		hint :=
			"" if topic == "odin" || topic == "odx" else fmt.tprintf("; see `odx explain %s --rule %s`", topic, rule)
		fmt.printfln("%s:%d:%d: %s %s%s", v.file, v.line, v.col, v.rule, v.message, hint)
	}
	for e in r.tool_errors {fmt.eprintln("odx: tool error:", e)}
	if len(r.violations) == 0 && len(r.tool_errors) == 0 {
		fmt.printfln("ok: %d files, %d ignored", r.summary.files, r.summary.ignored)
	}
}
