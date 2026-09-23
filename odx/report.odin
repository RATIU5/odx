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
	subject:       string, // rule-provided semantic label; baseline identity also binds source and position
	baselined:     bool, // listed in odx.baseline: printed, never fails the build
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

Rule_Metadata :: struct {
	check, class, statement, why, fix_hint, instead_of: string `json:",omitempty"`,
	fires, silent, evidence, boundary:                  string `json:",omitempty"`,
}

Report :: struct {
	schema:      int,
	rules:       map[string]Rule_Metadata,
	coverage:    Coverage,
	violations:  [dynamic]Violation,
	tool_errors: [dynamic]string,
	summary:     struct {
		errors, warnings, ignored, files, omitted, baselined: int,
	},
}

// violation_in_package: does this violation belong to the package rooted at `rel`?
// Violations name a file, the package directory itself, or "." for the root package.
violation_in_package :: proc(v: Violation, rel: string) -> bool {
	return dir_of(v.file) == rel || v.file == rel || (rel == "" && v.file == ".")
}

// note records an odin/* or odx/* finding: never ignorable, no rule class.
note :: proc(
	r: ^Report,
	rule, check, file: string,
	line, col: int,
	message: string,
	severity := Severity.error,
) {
	append(
		&r.violations,
		Violation {
			file = file,
			line = line,
			col = col,
			rule = rule,
			check = check,
			message = message,
			severity = severity,
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

finalize :: proc(r: ^Report, rb: ^Rulebook, strict: bool, max_violations := 0) -> int {
	r.schema = 2
	r.rules = make(map[string]Rule_Metadata)
	for entry in r.coverage.checks {
		r.rules[entry.rule] = Rule_Metadata {
			evidence = entry.evidence,
			boundary = entry.boundary,
		}
	}
	// One lookup per distinct rule: the rulebook owns this metadata, violations only name the rule.
	compiler := r.rules["odin/check"]
	seen := make(map[string]bool, context.temp_allocator)
	for v in r.violations {
		if seen[v.rule] {continue}
		seen[v.rule] = true
		metadata := r.rules[v.rule]
		rule := find_rule(rb, v.rule)
		if rule == nil {
			// odin/* and odx/* notes have no rule; compiler findings borrow its coverage.
			if v.check != "" {metadata.check = v.check}
			if v.check == "odin" {
				if metadata.evidence == "" {metadata.evidence = compiler.evidence}
				if metadata.boundary == "" {metadata.boundary = compiler.boundary}
			}
			r.rules[v.rule] = metadata
			continue
		}
		metadata.check = fmt.aprint(rule.check.kind)
		metadata.class = rule.class
		metadata.statement = rule.statement
		metadata.why = rule.why
		metadata.fix_hint = rule_fix_hint(rule)
		metadata.instead_of = rule.instead_of
		metadata.fires = rule.fires
		metadata.silent = rule.silent
		metadata.evidence, metadata.boundary = rule_evidence(rule.check)
		r.rules[v.rule] = metadata
	}
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
	seen := make(map[string]bool, context.temp_allocator)
	for v in r.violations {
		topic, _, rule := strings.partition(v.rule, "/")
		hint :=
			"" if topic == "odin" || topic == "odx" else fmt.tprintf("; see `odx policy --topic %s --rule %s`", topic, rule)
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
		if topic == "odin" || topic == "odx" {continue} // notes carry no rule metadata
		if v.rule in seen {continue}
		seen[v.rule] = true
		metadata := r.rules[v.rule]
		if metadata.fix_hint != "" {fmt.sbprintfln(&b, "  repair: %s", metadata.fix_hint)}
		if metadata.why != "" {fmt.sbprintfln(&b, "  why: %s", metadata.why)}
		if metadata.boundary !=
		   "" {fmt.sbprintfln(&b, "  evidence: %s; %s", metadata.evidence, metadata.boundary)}
	}
	if r.summary.omitted >
	   0 {fmt.sbprintfln(&b, "... %d more violations omitted (--max-violations)", r.summary.omitted)}
	return strings.to_string(b)
}
