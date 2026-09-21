package odx

import "core:fmt"
import "core:os"
import "core:strings"

// `odx doctor`: the toolchain and task-file drift report (sections 3, 17.11, 17.15, 20.3).
// Errors exit 2: config broken, odin missing, a forbidden flag in use, a dirty lock.
// Everything else is a warning, except version drift under --ci.

Doctor :: struct {
	errors, warnings: int,
}

warn :: proc(d: ^Doctor, f: string, args: ..any) {
	d.warnings += 1
	fmt.print("warning: ")
	fmt.printfln(f, ..args)
}

err :: proc(d: ^Doctor, f: string, args: ..any) {
	d.errors += 1
	fmt.print("error: ")
	fmt.printfln(f, ..args)
}

cmd_doctor :: proc(o: Opts) {
	p := must_load(o, true)
	c := make_ctx(&p, nil)
	d: Doctor
	check_toolchain(&d, &c, o.ci)
	check_task_files(&d, &p)
	// the canonical argv (20.3): the hook, CI and this all shell out to the same odin flags
	fmt.printfln(
		"expected test task: odin test . %s %s",
		strings.join(odin_flags(&c), " ", context.temp_allocator),
		strings.join(p.cfg.odin.required_flags, " ", context.temp_allocator),
	)
	check_attachment(&d, &c)
	if o.relock {write_lock(p.root)}
	if o.verify || o.ci {
		switch state, text := lock_check(p.root); state {
		case .missing:
			warn(&d, "no %s; %s", LOCK_FILE, LOCK_HINT)
		case .dirty:
			err(&d, "%s", text)
		case .clean:
			fmt.println("lock: ok")
		}
	}
	for t in p.rb.topics {if t.overrides {warn(&d, "topic %s is overridden by %s", t.name, t.source)}}
	for id in sorted_keys(p.cfg.disabled) {fmt.printfln("disabled: %s (%s)", id, p.cfg.disabled[id])}
	fmt.printfln("%d errors, %d warnings", d.errors, d.warnings)
	if d.errors > 0 {os.exit(EXIT_TOOL)}
}

// check_toolchain: odin runs, its version matches, and `odin check` accepts every config flag.
check_toolchain :: proc(d: ^Doctor, c: ^Ctx, ci: bool) {
	exe := odin_exe(c.cfg)
	version := odin_output(exe, "version")
	if version == "" {
		err(d, "cannot run %s (set odin.path in %s or ODX_ODIN)", exe, CONFIG_FILE)
		return
	}
	_, _, ver := strings.partition(version, "version ")
	fmt.printfln("odin: %s %s", exe, ver)
	if want := c.cfg.odin.version; want != "" && !strings.has_prefix(ver, want) {
		report := err if ci else warn
		report(d, "odin version %s does not match odin.version %s", ver, want)
	}
	help := odin_output(exe, "help", "check")
	for f in c.cfg.odin.flags {
		name, _, _ := strings.partition(f, ":")
		if !strings.contains(
			   help,
			   strings.concatenate({"\n\t", name, "\n"}, context.temp_allocator),
		   ) &&
		   !strings.contains(
				   help,
				   strings.concatenate({"\n\t", name, ":"}, context.temp_allocator),
			   ) {
			err(d, "flag %s is not accepted by `odin check` on this compiler", f)
		}
		if flag_listed(
			c.cfg.odin.forbidden_flags,
			f,
		) {err(d, "odin.flags contains forbidden flag %s", f)}
	}
}

// check_task_files: mise.toml carries the required flags and none of the forbidden ones; the
// hook config and CI workflow call odx rather than a copy of it (20.3).
check_task_files :: proc(d: ^Doctor, p: ^Project) {
	if mise, rerr := os.read_entire_file(join({p.root, "mise.toml"}), context.allocator);
	   rerr == nil {
		// tokens of every non-comment line: a comment naming a flag is not a use of it
		tokens := make(map[string]bool, context.temp_allocator)
		for line in strings.split_lines(string(mise), context.temp_allocator) {
			code, _, _ := strings.partition(line, "#")
			for tok in strings.fields(code, context.temp_allocator) {tokens[strings.trim(tok, "\"'")] = true}
		}
		for f in p.cfg.odin.forbidden_flags {
			if f in tokens {err(d, "mise.toml uses forbidden flag %s", f)}
		}
		for f in p.cfg.odin.required_flags {
			if f not_in tokens {warn(d, "mise.toml test task lacks required flag %s", f)}
		}
	} else {
		warn(d, "no mise.toml (odx init writes one)")
	}
	if hooks, herr := os.read_entire_file(
		join({p.root, ".claude", "settings.json"}),
		context.allocator,
	); herr == nil {
		for cmd in ([]string{"hook edit", "hook stop", "hook changed"}) {
			if !strings.contains(
				string(hooks),
				cmd,
			) {warn(d, ".claude/settings.json does not run `odx %s` (odx init --hooks prints the block)", cmd)}
		}
	}
	if ci, cerr := os.read_entire_file(
		join({p.root, ".github", "workflows", "ci.yml"}),
		context.allocator,
	); cerr == nil && !strings.contains(string(ci), "mise run ci") {
		warn(d, ".github/workflows/ci.yml does not run `mise run ci`")
	}
}

// check_attachment: a topic whose roles no package has never attaches (20.10).
check_attachment :: proc(d: ^Doctor, c: ^Ctx) {
	roles_in_use := make(map[string]bool, context.temp_allocator)
	for pk in c.pkgs {if pk.role_count == 1 {roles_in_use[pk.role] = true}}
	for t in c.rb.topics {
		attached := len(t.applies_to.roles) == 0
		for r in t.applies_to.roles {attached ||= roles_in_use[r]}
		if !attached {warn(d, "topic %s applies to roles %v but no package has one", t.name, t.applies_to.roles)}
	}
}

// odin_output runs odin with args and returns stdout+stderr trimmed, "" if it cannot run.
odin_output :: proc(exe: string, args: ..string) -> string {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, exe)
	append(&cmd, ..args)
	_, out, errb, perr := os.process_exec({command = cmd[:]}, context.allocator)
	if perr != nil {return ""}
	return strings.trim_space(strings.concatenate({string(out), string(errb)}))
}

// flag_listed: "-define:X=1" matches a listed "-define:X=1" or bare "-define".
flag_listed :: proc(list: []string, flag: string) -> bool {
	name, _, _ := strings.partition(flag, ":")
	for l in list {if l == flag || l == name {return true}}
	return false
}
