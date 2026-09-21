package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// Subprocess plugins (10a, M7): `odx-<name>` executables listed in odx.json5 `plugins`
// with a pinned sha256. Handshake `--describe`, then one run per check id with JSON on
// stdin/stdout. Any failure (bad hash, unknown protocol, non-zero exit, timeout, unparseable
// output) is a tool error, never a silent pass (13). Plugins are read-only by contract.

PLUGIN_PROTOCOL :: 1
PLUGIN_TIMEOUT :: 30 * time.Second // ponytail: one constant; per-plugin timeouts when someone needs one

Plugin_Describe :: struct {
	protocol: int,
	checks:   []string,
}

Plugin_Request :: struct {
	protocol: int,
	check:    string,
	root:     string,
	files:    []string,
}

Plugin_Response :: struct {
	violations: []struct {
		file:    string,
		line:    int,
		col:     int,
		rule:    string,
		message: string,
	},
}

// find_plugin resolves `.odx/plugins/odx-<name>` first, then `odx-<name>` on PATH.
find_plugin :: proc(root, name: string) -> string {
	exe := strings.concatenate({"odx-", name}, context.temp_allocator)
	local := join({root, ".odx", "plugins", exe})
	if os.exists(local) {return local}
	for dir in strings.split(os.get_env("PATH", context.temp_allocator), ":", context.temp_allocator) {
		p := join({dir, exe})
		if os.exists(p) {return p}
	}
	return ""
}

run_plugins :: proc(c: ^Ctx) {
	files := make([dynamic]string, context.temp_allocator)
	for p in c.pkgs {
		for f in p.files {
			rel, _ := rel_of(c.root, f.fullpath)
			append(&files, rel)
		}
	}
	for name in sorted_keys(c.cfg.plugins) {
		exe := find_plugin(c.root, name)
		if exe == "" {
			tool_error(c.r, "plugin %s: odx-%s not found in .odx/plugins or PATH", name, name)
			continue
		}
		data, rerr := os.read_entire_file(exe, context.temp_allocator)
		if rerr != nil {
			tool_error(c.r, "plugin %s: cannot read %s", name, exe)
			continue
		}
		if got := sha256_hex(data); got != c.cfg.plugins[name] {
			tool_error(c.r, "plugin %s: sha256 mismatch: odx.json5 pins %s, %s is %s", name, c.cfg.plugins[name], exe, got)
			continue
		}
		d: Plugin_Describe
		if !plugin_call(c, name, exe, {"--describe"}, "", &d) {continue}
		if d.protocol != PLUGIN_PROTOCOL {
			tool_error(c.r, "plugin %s: protocol %d, this odx speaks %d", name, d.protocol, PLUGIN_PROTOCOL)
			continue
		}
		for id in d.checks {
			req, _ := json.marshal(Plugin_Request{PLUGIN_PROTOCOL, id, c.root, files[:]}, allocator = context.temp_allocator)
			resp: Plugin_Response
			if !plugin_call(c, name, exe, nil, string(req), &resp) {continue}
			for v in resp.violations {
				append(&c.r.violations, Violation {
					file = v.file,
					line = max(v.line, 1),
					col = max(v.col, 1),
					rule = v.rule if v.rule != "" else id,
					check = fmt.aprintf("plugin:%s", name),
					message = v.message,
					// ponytail: not ignorable; plugin rule ids are unknown to the rulebook
				})
			}
		}
	}
}

// plugin_call runs exe with args, stdin from a temp file holding input, stdout to a temp file,
// and unmarshals stdout into out. ponytail: files instead of pipes, so a chatty plugin cannot
// deadlock the host; the timeout kills it.
plugin_call :: proc(c: ^Ctx, name, exe: string, args: []string, input: string, out: ^$T) -> bool {
	in_f, ierr := os.create_temp_file("", "odx-plugin-in-*")
	out_f, oerr := os.create_temp_file("", "odx-plugin-out-*")
	if ierr != nil || oerr != nil {
		tool_error(c.r, "plugin %s: cannot create temp files", name)
		return false
	}
	defer {
		os.remove(os.name(in_f))
		os.remove(os.name(out_f))
		os.close(in_f)
		os.close(out_f)
	}
	os.write_string(in_f, input)
	os.seek(in_f, 0, .Start)
	cmd := slice.concatenate([][]string{{exe}, args}, context.temp_allocator)
	p, serr := os.process_start({command = cmd, working_dir = c.root, stdin = in_f, stdout = out_f})
	if serr != nil {
		tool_error(c.r, "plugin %s: cannot start %s: %v", name, exe, serr)
		return false
	}
	state, werr := os.process_wait(p, PLUGIN_TIMEOUT)
	if werr == .Timeout {
		_ = os.process_kill(p)
		_, _ = os.process_wait(p)
		tool_error(c.r, "plugin %s: timed out after %v", name, PLUGIN_TIMEOUT)
		return false
	}
	text, _ := os.read_entire_file(os.name(out_f), context.allocator)
	if werr != nil || state.exit_code != 0 {
		tool_error(c.r, "plugin %s: exited %d (%v): %s", name, state.exit_code, werr, strings.trim_space(string(text)))
		return false
	}
	if uerr := json.unmarshal(text, out); uerr != nil {
		tool_error(c.r, "plugin %s: unparseable output: %v: %s", name, uerr, strings.trim_space(string(text)))
		return false
	}
	return true
}
