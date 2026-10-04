package odx

import "core:fmt"
import "core:io"
import "core:slice"
import "core:strings"

JSON_VERSION :: 1

Finding :: struct {
	path:      string,
	line:      int,
	col:       int,
	rule:      Rule,
	message:   string,
	held_back: bool,
	// The dir of the package the finding counts toward for `pending-stale`, or "" when none. Borrows
	// `Package.dir`. Compare and dedupe ignore it, so `stale_pending` reads it before dedupe.
	owner_dir: string,
}

Error :: struct {
	code:    Error_Code,
	message: string,
}

Result :: struct {
	findings: [dynamic]Finding,
	errors:   [dynamic]Error,
	ignored:  int,
	pending:  int,
	skipped:  int,
	// Stderr lines, such as what was skipped and why.
	notes:    [dynamic]string,
	rule_set: int,
	odin:     string,
}

// Rules order by ID, not enum position, because the ID is the contract.
finding_cmp :: proc(a, b: Finding) -> slice.Ordering {
	if a.held_back != b.held_back {
		return a.held_back ? .Greater : .Less
	}
	if c := strings.compare(a.path, b.path); c != 0 {
		return slice.Ordering(c)
	}
	if a.line != b.line {
		return slice.cmp(a.line, b.line)
	}
	if a.col != b.col {
		return slice.cmp(a.col, b.col)
	}
	if c := strings.compare(RULES[a.rule].id, RULES[b.rule].id); c != 0 {
		return slice.Ordering(c)
	}
	return slice.Ordering(strings.compare(a.message, b.message))
}

sort_and_dedupe_findings :: proc(findings: ^[dynamic]Finding) {
	slice.sort_by_cmp(findings[:], finding_cmp)
	same :: proc(a, b: Finding) -> bool {
		return finding_cmp(a, b) == .Equal
	}
	resize(findings, len(slice.unique_proc(findings[:], same)))
	drop_held_back_copies_of_shown(findings)
}

// Needs `findings` sorted and deduped by `finding_cmp`, which puts every shown finding before every
// held-back one, so the shown ones form a sorted prefix to binary search.
@(private = "file")
drop_held_back_copies_of_shown :: proc(findings: ^[dynamic]Finding) {
	shown_count := 0
	for shown_count < len(findings) && !findings[shown_count].held_back {
		shown_count += 1
	}
	shown := findings[:shown_count]
	kept := shown_count
	for f in findings[shown_count:] {
		unheld := f
		unheld.held_back = false
		if _, found := slice.binary_search_by(shown, unheld, finding_cmp); !found {
			findings[kept] = f
			kept += 1
		}
	}
	resize(findings, kept)
}

exit_code :: proc(result: Result) -> int {
	if len(result.errors) > 0 {
		return 2
	}
	for f in result.findings {
		if !f.held_back {
			return 1
		}
	}
	return 0
}

// Any error means no result, so findings and counts are not written.
// fmt's writer procs drop io errors, so each stream is built in memory and written once.
write_result :: proc(out, err: io.Writer, result: Result, cmd: Check_Command) -> io.Error {
	o := strings.builder_make()
	defer strings.builder_destroy(&o)
	e := strings.builder_make()
	defer strings.builder_destroy(&e)
	render_result(&o, &e, result, cmd)
	io.write_string(err, strings.to_string(e)) or_return
	io.write_string(out, strings.to_string(o)) or_return
	return nil
}

@(private = "file")
render_result :: proc(out, err: ^strings.Builder, result: Result, cmd: Check_Command) {
	for e in result.errors {
		fmt.sbprintf(err, "odx: error: %s: %s\n", ERROR_CODES[e.code], e.message)
	}
	failed := len(result.errors) > 0
	if !failed {
		for note in result.notes {
			fmt.sbprintf(err, "%s\n", note)
		}
	}
	if cmd.json {
		render_json(out, result, cmd, failed)
		return
	}
	if failed {
		return
	}

	count := 0
	for f in result.findings {
		if !f.held_back {
			count += 1
			render_finding_text(out, f)
		}
	}
	if cmd.pending && count < len(result.findings) {
		strings.write_string(err, "odx: pending findings:\n")
		for f in result.findings {
			if f.held_back {
				render_finding_text(out, f)
			}
		}
	}
	fmt.sbprintf(
		out,
		"odx: %d findings, %d ignored, %d pending, %d skipped (rules %d, odx %s, odin %s)\n",
		count,
		result.ignored,
		result.pending,
		result.skipped,
		result.rule_set,
		RELEASE,
		result.odin,
	)
}

render_finding_text :: proc(out: ^strings.Builder, f: Finding) {
	fmt.sbprintf(out, "%s:%d:%d: %s: %s\n", f.path, f.line, f.col, RULES[f.rule].id, f.message)
}

@(private = "file")
render_json :: proc(out: ^strings.Builder, result: Result, cmd: Check_Command, failed: bool) {
	fmt.sbprintf(out, `{{"version":%d,"findings":[`, JSON_VERSION)
	count := 0
	written := 0
	for f in result.findings {
		if failed || (f.held_back && !cmd.pending) {
			continue
		}
		if !f.held_back {
			count += 1
		}
		if written > 0 {
			strings.write_byte(out, ',')
		}
		written += 1
		strings.write_string(out, `{"path":`)
		render_json_string(out, f.path)
		fmt.sbprintf(
			out,
			`,"line":%d,"col":%d,"rule":"%s","message":`,
			f.line,
			f.col,
			RULES[f.rule].id,
		)
		render_json_string(out, f.message)
		if f.held_back {
			strings.write_string(out, `,"pending":true`)
		}
		strings.write_byte(out, '}')
	}
	strings.write_string(out, `],"errors":[`)
	for e, i in result.errors {
		if i > 0 {
			strings.write_byte(out, ',')
		}
		fmt.sbprintf(out, `{{"code":"%s","message":`, ERROR_CODES[e.code])
		render_json_string(out, e.message)
		strings.write_byte(out, '}')
	}
	ignored, pending, skipped := result.ignored, result.pending, result.skipped
	if failed {
		ignored, pending, skipped = 0, 0, 0
	}
	fmt.sbprintf(
		out,
		`],"summary":{{"findings":%d,"ignored":%d,"pending":%d,"skipped":%d,"rules":%d,"release":"%s","odin":`,
		count,
		ignored,
		pending,
		skipped,
		result.rule_set,
		RELEASE,
	)
	render_json_string(out, result.odin)
	strings.write_string(out, "}}\n")
}

@(private = "file")
render_json_string :: proc(out: ^strings.Builder, s: string) {
	strings.write_byte(out, '"')
	for i in 0 ..< len(s) {
		b := s[i]
		switch b {
		case '"':
			strings.write_string(out, `\"`)
		case '\\':
			strings.write_string(out, `\\`)
		case '\n':
			strings.write_string(out, `\n`)
		case '\r':
			strings.write_string(out, `\r`)
		case '\t':
			strings.write_string(out, `\t`)
		case 0 ..< 0x20:
			fmt.sbprintf(out, `\u%04x`, b)
		case:
			strings.write_byte(out, b)
		}
	}
	strings.write_byte(out, '"')
}
