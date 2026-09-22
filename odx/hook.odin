package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

// Hook findings are advisory: every configured edit invocation exits 0.
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
	_ = json.unmarshal(raw, &in_)
	p := load_project(o.root)
	if p.root == "" {return}
	for e in p.errs {fmt.println("odx:", e)}
	if len(p.errs) == 0 {hook_edit(&p, in_.tool_input.file_path)}
}

// Source and policy edits can affect unchanged importers. Batch input has no file path.
hook_edit :: proc(p: ^Project, file: string) {
	fo := Opts {
		fast           = true,
		max_violations = HOOK_MAX_VIOLATIONS,
	}
	reason := "hook source or policy edit triggers full current-project reporting, including unchanged dependents"
	if file != "" {
		rel, inside := rel_of(p.root, canonical(file))
		if inside {
			if !check_input(rel) {return}
		} else if !strings.has_suffix(file, ".odin") {return}
	} else {
		if files, ok := changed_check_inputs(p.root, "HEAD"); ok {
			if len(files) == 0 {return}
		} else {
			reason = "hook change discovery unavailable; full current-project reporting"
		}
	}
	c := make_ctx(p, nil)
	c.selection_reason = reason
	run_family_a(&c)
	run_checks(&c, fo)
	for e in c.r.tool_errors {fmt.println("odx: tool error:", e)}
	fmt.print(hook_text(c.r))
	fmt.print(coverage_text(c.r))
}
