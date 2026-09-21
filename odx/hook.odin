package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

// Claude Code hooks: input JSON arrives on stdin; exit 2 with text on stderr blocks and
// feeds the text back to the model, exit 0 lets it through.

Hook_Input :: struct {
	tool_input:       struct {
		file_path: string,
	},
	stop_hook_active: bool,
}

Hook :: enum {
	edit,
	changed,
	stop,
}

EXIT_HOOK_BLOCK :: 2 // Claude Code's "block and show stderr to the model"
GUARD_FILE :: ".odx/cache/stop-guard"
STOP_GUARD_DEFAULT :: 3
HOOK_MAX_VIOLATIONS :: 50

cmd_hook :: proc(o: Opts) {
	if len(o.args) != 1 {fail("usage: odx hook edit | stop | changed")}
	which, ok := reflect_enum(Hook, o.args[0])
	if !ok {fail("usage: odx hook edit | stop | changed")}
	raw, _ := os.read_entire_file_from_file(os.stdin, context.allocator)
	in_: Hook_Input
	_ = json.unmarshal(raw, &in_) // malformed input means "nothing to enforce", never a block
	p := load_project(o.root)
	if p.root == "" {return} 	// not an odx project
	if len(p.errs) > 0 {
		for e in p.errs {fmt.eprintln("odx:", e)}
		os.exit(EXIT_HOOK_BLOCK)
	}
	switch which {
	case .edit:
		hook_edit(&p, in_.tool_input.file_path)
	case .changed:
		// a protected path changed on disk: report lock drift, never refuse
		if state, text := lock_check(p.root); state == .dirty {fmt.eprintln(text)}
	case .stop:
		hook_stop(&p) // stop_hook_active is expected: the guard below bounds the loop, not the flag
	}
}

block :: proc(text: string) {
	fmt.eprint(text)
	if !strings.has_suffix(text, "\n") {fmt.eprintln()}
	os.exit(EXIT_HOOK_BLOCK)
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
		print_tool_errors(c.r)
		block(report_text(c.r))
	}
	c.r^ = {}
	run_checks(&c, fo)
	if hook_blocks(c.r) {
		print_tool_errors(c.r)
		block(hook_text(c.r))
	}
}

// Blocks on every Stop until clean. A repeat of identical output adds the topic exemplars;
// ODX_STOP_GUARD_MAX identical blocks (default 3) states the outcome and stops. Lock drift is
// printed, never blocked.
hook_stop :: proc(p: ^Project) {
	c := make_ctx(p, nil)
	run_checks(&c, Opts{max_violations = HOOK_MAX_VIOLATIONS})
	code := EXIT_VIOLATION if hook_blocks(c.r) else 0 // advisory rules never enter the loop
	text := hook_text(c.r)
	if n := c.r.summary.baselined;
	   n > 0 {text = fmt.tprintf("%sodx: %d baselined violations remain\n", text, n)}
	if n := len(added_ignores(p.root, project_ignores(&c))); n > 0 {
		text = fmt.tprintf(
			"%sodx: %d suppressions added since HEAD (odx ignores --added)\n",
			text,
			n,
		)
	}
	if state, lock_text := lock_check(p.root); state == .dirty {
		fmt.eprintln(lock_text)
	}
	guard := join({p.root, GUARD_FILE})
	if code == 0 {
		os.remove(guard)
		return
	}
	limit := STOP_GUARD_DEFAULT
	if v, ok := strconv.parse_int(os.get_env("ODX_STOP_GUARD_MAX", context.temp_allocator));
	   ok {limit = max(v, 1)} 	// 0 would disable the backstop
	switch n := guard_count(guard, text); {
	case n >= limit:
		fmt.eprint(text)
		fmt.eprintfln(
			"odx: loop guard exhausted after %d blocks; remaining violations are NOT fixed",
			n,
		)
		os.remove(guard)
	case n == 2:
		// the same text again means the model is stuck: show what passing looks like
		block(strings.concatenate({text, exemplars_for(&c)}))
	case:
		block(text)
	}
}

exemplars_for :: proc(c: ^Ctx) -> string {
	b := strings.builder_make()
	seen := make(map[string]bool, context.temp_allocator)
	for v in c.r.violations {
		topic, _, _ := strings.partition(v.rule, "/")
		if topic in seen {continue}
		seen[topic] = true
		if t := find_topic(c.rb, topic); t != nil && t.exemplar != "" {
			fmt.sbprintfln(
				&b,
				"\n// this compiles and passes every %s rule:\n%s",
				topic,
				t.exemplar,
			)
		}
	}
	return strings.to_string(b)
}

// guard_count returns how many consecutive stop blocks (including this one) had this output.
guard_count :: proc(path, text: string) -> int {
	key := sha256_hex(transmute([]byte)text)
	n := 1
	if old, err := os.read_entire_file(path, context.allocator); err == nil {
		cnt, _, prev := strings.partition(string(old), "\n")
		if prev == key {
			if v, ok := strconv.parse_int(cnt); ok {n = v + 1}
		}
	}
	os.make_directory_all(filepath.dir(path))
	write_atomic(path, fmt.tprintf("%d\n%s", n, key))
	return n
}
