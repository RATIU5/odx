package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Claude Code hook: input JSON arrives on stdin, findings go to stdout, exit is always 0.
// odx reports to the agent; it never refuses an edit and never holds a session open.

Hook_Input :: struct {
	tool_input: struct {
		file_path: string,
	},
}

HOOK_MAX_VIOLATIONS :: 50

cmd_hook :: proc(o: Opts) {
	if len(o.args) != 1 || o.args[0] != "edit" {fail("usage: odx hook edit")}
	raw, _ := os.read_entire_file_from_file(os.stdin, context.allocator)
	in_: Hook_Input
	_ = json.unmarshal(raw, &in_) // malformed input means "nothing to report"
	p := load_project(o.root)
	if p.root == "" {return} 	// not an odx project
	for e in p.errs {fmt.println("odx:", e)}
	if len(p.errs) == 0 {hook_edit(&p, in_.tool_input.file_path)}
}

// file is empty for PostToolBatch, which carries no single file_path.
hook_edit :: proc(p: ^Project, file: string) {
	fo := Opts {
		fast           = true,
		max_violations = HOOK_MAX_VIOLATIONS,
	}
	if file != "" {
		if !strings.has_suffix(file, ".odin") {return}
		abs := canonical(file)
		rel, inside := rel_of(p.root, filepath.dir(abs))
		// a file outside the root or excluded narrows nothing: check the whole project
		if inside && !is_excluded(&p.cfg, rel) {append(&fo.args, abs)}
	} else {
		// changed files since HEAD; outside git, everything
		if files, in_git := changed_odin_files(p.root, "HEAD"); in_git {
			if len(files) == 0 {return}
			append(&fo.args, ..files)
		}
	}
	c := make_ctx(p, fo.args[:])
	// the compiler is ground truth and never a false positive: it goes first, alone
	for pk in c.pkgs {
		for d in pk.diags {
			rel, _ := rel_of(c.root, d.pos.file)
			note(c.r, "odin/syntax", "parse", rel, d.pos.line, d.pos.column, d.msg)
		}
	}
	if len(c.r.violations) == 0 {run_family_a(&c)}
	if finalize(c.r, false, HOOK_MAX_VIOLATIONS) != 0 {
		for e in c.r.tool_errors {fmt.println("odx: tool error:", e)}
		fmt.print(report_text(c.r))
		return
	}
	c.r^ = {}
	run_checks(&c, fo)
	for e in c.r.tool_errors {fmt.println("odx: tool error:", e)}
	fmt.print(hook_text(c.r))
}
