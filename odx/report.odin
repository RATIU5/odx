package odx

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

// Finding is one rule violation. line is 0 when it isn't tied to a line.
Finding :: struct {
	file:    string,
	line:    int,
	rule:    string,
	message: string,
}

// Report is everything one command produced. errors are reasons odx couldn't do its job.
Report :: struct {
	findings: [dynamic]Finding,
	errors:   [dynamic]string,
	ignores:  int,
}

finding_less :: proc(a, b: Finding) -> bool {
	if a.file != b.file {return a.file < b.file}
	if a.line != b.line {return a.line < b.line}
	if a.rule != b.rule {return a.rule < b.rule}
	return a.message < b.message
}

// finish sorts the findings and drops exact duplicates.
finish :: proc(r: ^Report) {
	slice.sort_by(r.findings[:], finding_less)
	kept := slice.unique(r.findings[:])
	resize(&r.findings, len(kept))
}

exit_code :: proc(r: Report) -> int {
	if len(r.errors) > 0 {return 2}
	if len(r.findings) > 0 {return 1}
	return 0
}

write_text :: proc(r: Report, out, err: ^strings.Builder) {
	for f in r.findings {
		if f.line > 0 {
			fmt.sbprintfln(out, "%s:%d: %s: %s", f.file, f.line, f.rule, f.message)
		} else {
			fmt.sbprintfln(out, "%s: %s: %s", f.file, f.rule, f.message)
		}
	}
	for e in r.errors {
		fmt.sbprintfln(err, "odx: %s", e)
	}
	fmt.sbprintfln(err, "findings: %d  ignores: %d", len(r.findings), r.ignores)
}

write_json :: proc(r: Report, out: ^strings.Builder) {
	opt: json.Marshal_Options
	_ = json.marshal_to_builder(out, r, &opt)
	strings.write_byte(out, '\n')
}
