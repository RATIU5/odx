package odx

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:slice"
import "core:strings"

// Rule is a rule ID from SCOPE. The published name in RULE_NAMES is permanent and never
// reused; the enum order is internal. `all` and `package-target` are reserved, not rules.
Rule :: enum {
	compiler,
	package_role,
	explicit_allocators,
	vet_negation,
	temp_allocator,
	dynamic_allocator,
	require_results,
	mutable_state,
	init_proc,
	import_boundary,
	self_contained,
	unused_ignore,
	invalid_ignore,
	test_failed,
	leak,
	bad_free,
	panic,
	crash,
	address,
}

// RULE_NAMES are the published rule IDs, as they appear in output and in ignores.
@(rodata)
RULE_NAMES := [Rule]string {
	.compiler            = "compiler",
	.package_role        = "package-role",
	.explicit_allocators = "explicit-allocators",
	.vet_negation        = "vet-negation",
	.temp_allocator      = "temp-allocator",
	.dynamic_allocator   = "dynamic-allocator",
	.require_results     = "require-results",
	.mutable_state       = "mutable-state",
	.init_proc           = "init-proc",
	.import_boundary     = "import-boundary",
	.self_contained      = "self-contained",
	.unused_ignore       = "unused-ignore",
	.invalid_ignore      = "invalid-ignore",
	.test_failed         = "test-failed",
	.leak                = "leak",
	.bad_free            = "bad-free",
	.panic               = "panic",
	.crash               = "crash",
	.address             = "address",
}

// Finding is one rule violation. path is repo-relative with `/`; line and column are
// 1-based, and 0 when the finding has no position.
Finding :: struct {
	path:    string,
	line:    int,
	column:  int,
	rule:    Rule,
	message: string,
}

// Reason is why odx couldn't do its job (exit 2). path "" and line 0 mean absent.
Reason :: struct {
	path:    string,
	line:    int,
	column:  int,
	message: string,
}

// Report is everything one command produced. Every stage appends to the same one.
Report :: struct {
	findings: [dynamic]Finding,
	reasons:  [dynamic]Reason,
	ignores:  int,
}

finding_less :: proc(a, b: Finding) -> bool {
	if a.path != b.path {return a.path < b.path}
	if a.line != b.line {return a.line < b.line}
	if a.column != b.column {return a.column < b.column}
	if a.rule != b.rule {return RULE_NAMES[a.rule] < RULE_NAMES[b.rule]}
	return a.message < b.message
}

reason_less :: proc(a, b: Reason) -> bool {
	if a.path != b.path {return a.path < b.path}
	if a.line != b.line {return a.line < b.line}
	if a.column != b.column {return a.column < b.column}
	return a.message < b.message
}

// finish joins every message onto one line, then sorts findings and reasons and drops
// exact duplicates. Output procs expect a finished report.
finish :: proc(r: ^Report) {
	for &f in r.findings {
		f.message = one_line(f.message)
	}
	for &e in r.reasons {
		e.message = one_line(e.message)
	}
	slice.sort_by(r.findings[:], finding_less)
	resize(&r.findings, len(slice.unique(r.findings[:])))
	slice.sort_by(r.reasons[:], reason_less)
	resize(&r.reasons, len(slice.unique(r.reasons[:])))
}

// one_line joins the lines of s with single spaces, trimming each and dropping blank ones.
// It returns s itself when s is already one line.
one_line :: proc(s: string) -> string {
	if !strings.contains_any(s, "\r\n") {return s}
	b: strings.Builder
	rest, _ := strings.replace_all(s, "\r", "\n")
	for line in strings.split_lines_iterator(&rest) {
		trimmed := strings.trim_space(line)
		if trimmed == "" {continue}
		if strings.builder_len(b) > 0 {strings.write_byte(&b, ' ')}
		strings.write_string(&b, trimmed)
	}
	return strings.to_string(b)
}

exit_code :: proc(r: Report) -> int {
	if len(r.reasons) > 0 {return 2}
	if len(r.findings) > 0 {return 1}
	return 0
}

// write_text prints findings to stdout and reasons plus the summary line to stderr.
@(require_results)
write_text :: proc(r: Report, stdout, stderr: io.Writer) -> io.Error {
	out, err: strings.Builder
	for f in r.findings {
		name := RULE_NAMES[f.rule]
		if f.line > 0 {
			fmt.sbprintfln(&out, "%s:%d:%d: %s: %s", f.path, f.line, f.column, name, f.message)
		} else {
			fmt.sbprintfln(&out, "%s: %s: %s", f.path, name, f.message)
		}
	}
	for e in r.reasons {
		switch {
		case e.path == "":
			fmt.sbprintfln(&err, "odx: %s", e.message)
		case e.line > 0:
			fmt.sbprintfln(&err, "odx: %s:%d:%d: %s", e.path, e.line, e.column, e.message)
		case:
			fmt.sbprintfln(&err, "odx: %s: %s", e.path, e.message)
		}
	}
	fmt.sbprintfln(&err, "findings: %d  ignores: %d", len(r.findings), r.ignores)
	io.write_string(stdout, strings.to_string(out)) or_return
	io.write_string(stderr, strings.to_string(err)) or_return
	return nil
}

// Json_Output is the --json schema, version 1. It is separate from Report so internal
// changes can't change the published schema. Keys may be added; changing or removing
// one needs a new version.
Json_Output :: struct {
	version:  int,
	findings: []Json_Finding,
	errors:   []Json_Error,
	ignores:  int,
}

Json_Finding :: struct {
	path:    string,
	line:    int,
	column:  int,
	rule:    string,
	message: string,
}

Json_Error :: struct {
	path:    string,
	line:    int,
	column:  int,
	message: string,
}

// write_json prints the report as one JSON object on stdout. Nothing is written if
// marshalling fails.
@(require_results)
write_json :: proc(r: Report, stdout: io.Writer) -> json.Marshal_Error {
	o := Json_Output {
		version  = 1,
		findings = make([]Json_Finding, len(r.findings)),
		errors   = make([]Json_Error, len(r.reasons)),
		ignores  = r.ignores,
	}
	for f, i in r.findings {
		o.findings[i] = {f.path, f.line, f.column, RULE_NAMES[f.rule], f.message}
	}
	for e, i in r.reasons {
		o.errors[i] = {e.path, e.line, e.column, e.message}
	}
	b: strings.Builder
	opt: json.Marshal_Options
	json.marshal_to_builder(&b, o, &opt) or_return
	strings.write_byte(&b, '\n')
	io.write_string(stdout, strings.to_string(b)) or_return
	return nil
}
