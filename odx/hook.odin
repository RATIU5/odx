package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

// Claude Code hooks (17.10, 20.3). Input JSON arrives on stdin; exit 2 with text on stderr
// blocks and feeds the text back to the model, exit 0 lets it through.
//   hook edit:    family B on the edited file's package only (--fast); parse errors first.
//   hook changed: a protected path changed on disk; the lock says whether that is approved.
//   hook stop:    the full check plus the lock. It blocks on every Stop, including the ones
//                 with stop_hook_active set, until clean. Loop guard: after ODX_STOP_GUARD_MAX
//                 (default 3) consecutive blocks with the same output it gives up loudly.

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
STOP_GUARD_DEFAULT :: 3 // stricter than the harness cap of 8, deliberately (20.3)
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
		if state, text := lock_check(p.root); state == .dirty {block(text)}
	case .stop:
		hook_stop(&p) // stop_hook_active is expected: the guard below bounds the loop, not the flag
	}
}

block :: proc(text: string) {
	fmt.eprint(text)
	if !strings.has_suffix(text, "\n") {fmt.eprintln()}
	os.exit(EXIT_HOOK_BLOCK)
}

// hook_edit: PostToolBatch carries no single file_path; then the whole project, family B only.
hook_edit :: proc(p: ^Project, file: string) {
	fo := Opts {
		fast           = true,
		max_violations = HOOK_MAX_VIOLATIONS,
	}
	if file != "" {
		if !strings.has_suffix(file, ".odin") {return}
		abs := canonical(file)
		rel, inside := rel_of(p.root, filepath.dir(abs))
		// a file outside the root or excluded narrows nothing: check the whole project (17.10)
		if inside && !is_excluded(&p.cfg, rel) {append(&fo.args, abs)}
	}
	c := make_ctx(p, fo.args[:])
	if run_checks(&c, fo) != 0 {
		print_tool_errors(c.r)
		block(report_text(c.r))
	}
}

hook_stop :: proc(p: ^Project) {
	c := make_ctx(p, nil)
	code := run_checks(&c, Opts{max_violations = HOOK_MAX_VIOLATIONS})
	text := report_text(c.r)
	if state, lock_text := lock_check(p.root); state == .dirty {
		text = strings.concatenate({text, lock_text, "\n"})
		code = max(code, EXIT_VIOLATION)
	}
	guard := join({p.root, GUARD_FILE})
	if code == 0 {
		os.remove(guard)
		return
	}
	limit := STOP_GUARD_DEFAULT
	if v, ok := strconv.parse_int(os.get_env("ODX_STOP_GUARD_MAX", context.temp_allocator));
	   ok {limit = max(v, 1)} 	// 0 would disable the backstop
	if n := guard_count(guard, text); n > limit {
		fmt.eprint(text)
		fmt.eprintfln(
			"odx: loop guard exhausted after %d blocks; remaining violations are NOT fixed",
			n - 1,
		)
		os.remove(guard)
		return
	}
	block(text)
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
