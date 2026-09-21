package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// Subprocess plugins (10a, M7): `odx-<name>` executables listed in odx.json5 `plugins`
// with a pinned sha256. One run per plugin: the request lists the project's files on stdin,
// the response declares the plugin's check ids and its violations on stdout. Any failure
// (bad hash, unknown protocol, non-zero exit, timeout, unparseable output, an id that
// shadows the rulebook, a file outside the project) is a tool error, never a silent pass (13).
// Plugins are read-only by contract; the host enforces the half it can see.

PLUGIN_PROTOCOL :: 1
PLUGIN_TIMEOUT :: 30 * time.Second // ponytail: one constant; per-plugin timeouts when someone needs one

Plugin_Request :: struct {
	protocol: int,
	root:     string,
	files:    []string, // relative to root
}

Plugin_Response :: struct {
	protocol:   int,
	checks:     []string, // rule ids this plugin owns, e.g. "myproj/no-raw-sockets"
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
		if dir == "" {continue} 	// an empty PATH entry means cwd; never run a plugin from there
		p := join({dir, exe})
		if os.exists(p) {return p}
	}
	return ""
}

run_plugins :: proc(c: ^Ctx) {
	files := make([dynamic]string, context.temp_allocator)
	known := make(map[string]bool, context.temp_allocator)
	for p in c.pkgs {
		for f in p.files {
			rel, _ := rel_of(c.root, f.fullpath)
			append(&files, rel)
			known[rel] = true
		}
	}
	req, _ := json.marshal(
		Plugin_Request{PLUGIN_PROTOCOL, c.root, files[:]},
		allocator = context.temp_allocator,
	)
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
			tool_error(
				c.r,
				"plugin %s: sha256 mismatch: odx.json5 pins %s, %s is %s",
				name,
				c.cfg.plugins[name],
				exe,
				got,
			)
			continue
		}
		resp: Plugin_Response
		if !plugin_call(c, name, exe, string(req), &resp) {continue}
		if msg := plugin_validate(c, &resp, known); msg != "" {
			tool_error(c.r, "plugin %s: %s", name, msg)
			continue
		}
		check := fmt.aprintf("plugin:%s", name)
		for v in resp.violations {
			append(
				&c.r.violations,
				Violation {
					file    = v.file,
					line    = max(v.line, 1),
					col     = max(v.col, 1),
					rule    = v.rule,
					check   = check,
					message = v.message,
					// ponytail: not ignorable; plugin rule ids are unknown to the rulebook
				},
			)
		}
	}
}

// plugin_validate: the response speaks this protocol, owns at least one id that shadows
// nothing in the rulebook, and every violation is one of its ids on a file odx scanned.
plugin_validate :: proc(c: ^Ctx, resp: ^Plugin_Response, known: map[string]bool) -> string {
	if resp.protocol != PLUGIN_PROTOCOL {
		return fmt.tprintf("protocol %d, this odx speaks %d", resp.protocol, PLUGIN_PROTOCOL)
	}
	if len(resp.checks) == 0 {return "declares no checks"}
	for id in resp.checks {
		topic, _, rule := strings.partition(id, "/")
		if topic == "" || rule == "" {return fmt.tprintf("check id %q is not <topic>/<rule>", id)}
		if topic == "odx" || topic == "odin" || find_topic(c.rb, topic) != nil {
			return fmt.tprintf("check id %q shadows a rulebook topic", id)
		}
	}
	for v in resp.violations {
		if !slice.contains(resp.checks, v.rule) {
			return fmt.tprintf("violation rule %q is not one of its declared checks", v.rule)
		}
		if v.file not_in
		   known {return fmt.tprintf("violation names %q, a file odx did not scan", v.file)}
	}
	return ""
}

// plugin_call runs exe with stdin from a temp file holding input and stdout to a temp file,
// then unmarshals stdout into out. ponytail: files instead of pipes, so a chatty plugin cannot
// deadlock the host; the timeout kills it.
plugin_call :: proc(c: ^Ctx, name, exe, input: string, out: ^$T) -> bool {
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
	p, serr := os.process_start(
		{command = {exe}, working_dir = c.root, stdin = in_f, stdout = out_f},
	)
	if serr != nil {
		tool_error(c.r, "plugin %s: cannot start %s: %v", name, exe, serr)
		return false
	}
	state, werr := os.process_wait(p, plugin_timeout)
	if werr == .Timeout {
		_ = os.process_kill(p)
		_, _ = os.process_wait(p)
		tool_error(c.r, "plugin %s: timed out after %v", name, plugin_timeout)
		return false
	}
	text, _ := os.read_entire_file(os.name(out_f), context.allocator)
	if werr != nil || state.exit_code != 0 {
		tool_error(
			c.r,
			"plugin %s: exited %d (%v): %s",
			name,
			state.exit_code,
			werr,
			strings.trim_space(string(text)),
		)
		return false
	}
	if uerr := json.unmarshal(text, out); uerr != nil {
		tool_error(
			c.r,
			"plugin %s: unparseable output: %v: %s",
			name,
			uerr,
			strings.trim_space(string(text)),
		)
		return false
	}
	return true
}

plugin_timeout := PLUGIN_TIMEOUT // a variable so the test can exercise the kill path
