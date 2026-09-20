package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

// Claude Code hooks (17.10, 20.3). Input JSON arrives on stdin; exit 2 with text on stderr
// blocks and feeds the text back to the model, exit 0 lets it through.
//   hook edit: family B on the edited file's package only (--fast); parse errors first.
//   hook stop: the full check plus the protected-path lock. Loop guard: after
//   ODX_STOP_GUARD_MAX (default 5) consecutive blocks with the same output it gives up loudly.

Hook_Input :: struct {
	tool_input:       struct {
		file_path: string,
	},
	stop_hook_active: bool,
}

GUARD_FILE :: ".odx/cache/stop-guard"
STOP_GUARD_DEFAULT :: 3 // stricter than the harness cap of 8, deliberately (20.3)
HOOK_MAX_VIOLATIONS :: 50

cmd_hook :: proc(o: Opts) {
	if len(o.args) != 1 ||
	   !slice.contains(
			   []string{"edit", "stop", "changed"},
			   o.args[0],
		   ) {fail("usage: odx hook edit | stop | changed")}
	raw, _ := os.read_entire_file_from_file(os.stdin, context.allocator)
	in_: Hook_Input
	_ = json.unmarshal(raw, &in_)
	p := load_project(o.root)
	if p.root == "" {return} 	// not an odx project: nothing to enforce
	if len(p.errs) > 0 {
		for e in p.errs {fmt.eprintln("odx:", e)}
		os.exit(2)
	}
	switch o.args[0] {
	case "edit":
		// PostToolBatch carries no single file_path: then the whole project, family B only
		fo := Opts {
			fast           = true,
			max_violations = HOOK_MAX_VIOLATIONS,
		}
		if f := in_.tool_input.file_path; f != "" {
			if !strings.has_suffix(f, ".odin") {return}
			rel, inside := rel_of(p.root, f)
			if !inside || is_excluded(&p.cfg, rel) {return}
			append(&fo.args, f)
		}
		r, code := run_checks(&p, fo)
		if code != 0 {
			fmt.eprint(report_text(r))
			for e in r.tool_errors {fmt.eprintln("odx: tool error:", e)}
			os.exit(2)
		}
	case "changed":
		// FileChanged on a protected path: a sed -i bypasses PostToolUse, the hash does not (20.3)
		if diff, has := verify_lock(p.root); has && len(diff) > 0 {
			fmt.eprintfln(
				"odx: protected files changed; a human approves with ODX_ALLOW_PROTECTED=1 odx doctor --relock:\n  %s",
				strings.join(diff, "\n  "),
			)
			os.exit(2)
		}
		os.exit(0)
	case "stop":
		if in_.stop_hook_active {return}
		r, code := run_checks(&p, Opts{max_violations = HOOK_MAX_VIOLATIONS})
		text := report_text(r)
		if diff, has := verify_lock(p.root); has && len(diff) > 0 {
			text = strings.concatenate(
				{
					text,
					"protected files changed (17.9); a human approves with ODX_ALLOW_PROTECTED=1 odx doctor --relock:\n  ",
					strings.join(diff, "\n  "),
					"\n",
				},
			)
			code = max(code, EXIT_VIOLATION)
		}
		guard := join({p.root, GUARD_FILE})
		if code == 0 {
			os.remove(guard)
			return
		}
		n := guard_count(guard, text)
		limit := STOP_GUARD_DEFAULT
		if v, ok := strconv.parse_int(os.get_env("ODX_STOP_GUARD_MAX", context.temp_allocator));
		   ok {limit = v}
		fmt.eprint(text)
		if n > limit {
			fmt.eprintfln(
				"odx: loop guard exhausted after %d blocks; remaining violations are NOT fixed",
				n - 1,
			)
			os.remove(guard)
			return
		}
		os.exit(2)
	}
}

// guard_count returns how many consecutive stop blocks (including this one) had this output.
guard_count :: proc(path, text: string) -> int {
	digest := fmt.tprintf("%x", len(text)) // ponytail: length+prefix, not a hash; identical sets are what we care about
	key := strings.concatenate({digest, ":", text[:min(len(text), 200)]}, context.temp_allocator)
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
