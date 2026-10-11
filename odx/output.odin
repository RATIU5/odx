package odx

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:slice"
import "core:strings"

JSON_VERSION :: 1

MUTED_LINE :: "odx: %s: compile errors hide this package's other findings"

// `odin check` leaves a file tagged `#+test` out, and only `odin test` compiles it, which odx can't
// run (ADR 0005).
TEST_TAGGED_LINE :: "odx: %s: the compiler doesn't check %d files tagged #+test"

RETRIES_LINE :: "odx: the compiler died by a signal %d times, and odx ran it again each time\n"

HELP :: `odx checks Odin code against one standard.

Usage:
  odx check [--json] [--pending]
  odx init
  odx --help
  odx --version

  odx check      Checks every package under the repo root and prints the findings.
    --json       Prints the same result as one JSON document on stdout.
    --pending    Also prints the held-back findings of pending packages.
  odx init       Writes odx.json and odinfmt.json for a repo that has no odx.json.
  odx --help     Prints this text.
  odx --version  Prints the release, its rule set and the compiler it supports.

Exit codes:
  0  No findings.
  1  At least one finding.
  2  An error: odx can't give a trustworthy result.
`

Finding :: struct {
	path:      string,
	line:      int,
	col:       int,
	rule:      Rule,
	message:   string,
	// A stderr line that is printed when the finding is, and "" for none. Compare and dedupe ignore
	// it.
	note:      string,
	held_back: bool,
	// The dir of the package the finding counts toward for `pending-stale`, or "" when none.
	// Borrows `Package.dir`. Compare and dedupe ignore it, so `stale_pending` reads it before
	// dedupe.
	owner_dir: string,
}

Error :: struct {
	code:    Error_Code,
	message: string,
}

// A stderr line of a run that has a result. `held_back` says it is about a pending package, so it
// prints only with `--pending`.
Note :: struct {
	text:      string,
	held_back: bool,
}

Result :: struct {
	findings:         [dynamic]Finding,
	errors:           [dynamic]Error,
	ignored:          int,
	pending:          int,
	skipped:          int,
	// In print order: the skipped packages, those with `#+test` files, then those with dropped
	// findings.
	notes:            [dynamic]Note,
	// How many times a signal ended the compiler and odx ran it again.
	compiler_retries: int,
	rule_set:         int,
	odin:             string,
}

// What the release supports, which is not what the working directory's repo pins. Allocates the
// line with `allocator`.
version_line :: proc(allocator: runtime.Allocator) -> string {
	return fmt.aprintf(
		"odx %s, rule set %d, odin %s\n",
		RELEASE,
		RULE_SET,
		SUPPORTED_COMPILER,
		allocator = allocator,
	)
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
			if cmd.pending || !note.held_back {
				fmt.sbprintf(err, "%s\n", note.text)
			}
		}
	}
	// A run that ends in an error still says how often the compiler crashed.
	if result.compiler_retries > 0 {
		fmt.sbprintf(err, RETRIES_LINE, result.compiler_retries)
	}
	if !failed {
		render_finding_notes(err, result.findings[:], false)
	}
	if cmd.json {
		if !failed && cmd.pending {
			render_finding_notes(err, result.findings[:], true)
		}
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
		strings.write_string(err, "odx: held-back findings:\n")
		render_finding_notes(err, result.findings[:], true)
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

@(private = "file")
render_finding_notes :: proc(err: ^strings.Builder, findings: []Finding, held_back: bool) {
	for f in findings {
		if f.held_back == held_back && f.note != "" {
			fmt.sbprintf(err, "%s\n", f.note)
		}
	}
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
			strings.write_string(out, `,"held_back":true`)
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
		`],"summary":{{"findings":%d,"ignored":%d,"pending":%d,"skipped":%d,"rules":%d,` +
		`"release":"%s","odin":`,
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
