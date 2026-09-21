package odx

import "core:fmt"
import "core:os"
import "core:strings"

// `odx doctor`: the toolchain and task-file drift report.
// Errors exit 2: config broken, odin missing, a forbidden flag in use.
// Everything else is a warning, except version drift under --ci.

Doctor :: struct {
	errors, warnings: [dynamic]string,
	json:             bool, // collect only; the free-text sections are skipped and the lists printed once
	guarantees:       Guarantees_Report,
}

warn :: proc(d: ^Doctor, f: string, args: ..any) {
	append(&d.warnings, fmt.aprintf(f, ..args))
	if !d.json {fmt.println("warning:", d.warnings[len(d.warnings) - 1])}
}

err :: proc(d: ^Doctor, f: string, args: ..any) {
	append(&d.errors, fmt.aprintf(f, ..args))
	if !d.json {fmt.println("error:", d.errors[len(d.errors) - 1])}
}

// say: an informational line, text mode only.
say :: proc(d: ^Doctor, f: string, args: ..any) {
	if !d.json {fmt.printfln(f, ..args)}
}

doctor_exit :: proc(d: ^Doctor) {
	if d.json {
		print_json(
			struct {
				schema:     int,
				errors:     []string,
				warnings:   []string,
				guarantees: struct {
					flags:  []Guarantee,
					tagged: int,
					needed: int,
				},
			}{1, d.errors[:], d.warnings[:], {d.guarantees.flags[:], d.guarantees.tagged, d.guarantees.needed}},
		)
	} else {
		fmt.printfln("%d errors, %d warnings", len(d.errors), len(d.warnings))
	}
	if len(d.errors) > 0 {os.exit(EXIT_TOOL)}
}

cmd_doctor :: proc(o: Opts) {
	p := load_project(o.root)
	d := Doctor {
		json = o.json,
	}
	if p.root == "" {
		// no odx.json5: guarantees are reported against an empty flag set, so all read "off"
		warn(
			&d,
			"no %s here or in any parent; `odx init` writes one with the default guarantees",
			CONFIG_FILE,
		)
		p.root, _ = os.get_working_directory(context.allocator)
		if o.root != "" {p.root = canonical(o.root)}
		p.cfg.exclude = {".*", ".*/**", "build/**", "vendor/**"}
		p.dirs = package_dirs(p.root, &p.cfg)
	}
	for e in p.errs {err(&d, "%s", e)}
	if len(d.errors) > 0 {doctor_exit(&d)}
	c := make_ctx(&p, nil)
	hf := parse_help_flags(odin_output(odin_exe(c.cfg), "help", "check"))
	check_toolchain(&d, &c, o.ci, hf)
	report_guarantees(&d, &c, hf)
	check_task_files(&d, &p)
	say(&d, "check argv: odx check  (mise task, CI via `mise run ci`)")
	say(
		&d,
		"expected test task: odin test . %s %s",
		strings.join(odin_flags(&c), " ", context.temp_allocator),
		strings.join(p.cfg.odin.required_flags, " ", context.temp_allocator),
	)
	check_attachment(&d, &c)
	for t in p.rb.topics {if t.overrides {warn(&d, "topic %s is overridden by %s", t.name, t.source)}}
	for id in sorted_keys(p.cfg.disabled) {say(&d, "disabled: %s (%s)", id, p.cfg.disabled[id])}
	doctor_exit(&d)
}

check_toolchain :: proc(d: ^Doctor, c: ^Ctx, ci: bool, hf: Help_Flags) {
	exe := odin_exe(c.cfg)
	version := odin_output(exe, "version")
	if version == "" {
		err(d, "cannot run %s (set odin.path in %s or ODX_ODIN)", exe, CONFIG_FILE)
		return
	}
	_, _, ver := strings.partition(version, "version ")
	say(d, "odin: %s %s", exe, ver)
	if want := c.cfg.odin.version; want != "" && !strings.has_prefix(ver, want) {
		report := err if ci else warn
		report(d, "odin version %s does not match odin.version %s", ver, want)
	}
	for f in c.cfg.odin.flags {
		name, _, _ := strings.partition(f, ":")
		// an unreadable help text is report_guarantees' one warning, never an error here
		if hf.ok && name not_in hf.flags {
			err(d, "flag %s is not accepted by `odin check` on this compiler", f)
		}
		if flag_listed(
			c.cfg.odin.forbidden_flags,
			f,
		) {err(d, "odin.flags contains forbidden flag %s", f)}
	}
}

check_task_files :: proc(d: ^Doctor, p: ^Project) {
	if mise, rerr := os.read_entire_file(join({p.root, "mise.toml"}), context.allocator);
	   rerr == nil {
		// tokens of every non-comment line: a comment naming a flag is not a use of it
		tokens := make(map[string]bool, context.temp_allocator)
		for line in strings.split_lines(string(mise), context.temp_allocator) {
			for tok in strings.fields(toml_code(line), context.temp_allocator) {tokens[strings.trim(tok, "\"'")] = true}
		}
		for f in p.cfg.odin.forbidden_flags {
			if f in tokens {err(d, "mise.toml uses forbidden flag %s", f)}
		}
		for f in p.cfg.odin.required_flags {
			if f not_in tokens {warn(d, "mise.toml test task lacks required flag %s", f)}
		}
		if !strings.contains(string(mise), "odx check") &&
		   !strings.contains(
				   string(mise),
				   "ODX check",
			   ) {warn(d, "no mise.toml task runs `odx check`; CI and the hook would drift from it")}
	} else {
		warn(d, "no mise.toml (odx init writes one)")
	}
	if hooks, herr := os.read_entire_file(
		join({p.root, ".claude", "settings.json"}),
		context.allocator,
	); herr == nil {
		if !strings.contains(
			uncommented_json(string(hooks)),
			"hook edit",
		) {warn(d, ".claude/settings.json does not run `odx hook edit` (odx init --hooks prints the block)")}
	}
	if ci, cerr := os.read_entire_file(
		join({p.root, ".github", "workflows", "ci.yml"}),
		context.allocator,
	); cerr == nil && !strings.contains(string(ci), "mise run ci") {
		warn(d, ".github/workflows/ci.yml does not run `mise run ci`")
	}
}

// toml_code: the line up to the first `#` that is outside a quoted string.
// ponytail: a `'''` block is scanned line by line, so a `#` inside one still ends the line;
// flags inside such blocks sit before any `#` in practice.
toml_code :: proc(line: string) -> string {
	quote: byte
	for c, i in transmute([]byte)line {
		switch {
		case quote != 0:
			if c == quote {quote = 0}
		case c == '"' || c == '\'':
			quote = c
		case c == '#':
			return line[:i]
		}
	}
	return line
}

// uncommented_json drops `//` comment lines, so a commented-out hook is not a hook.
uncommented_json :: proc(text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for l in strings.split_lines(text, context.temp_allocator) {
		if strings.has_prefix(strings.trim_left_space(l), "//") {continue}
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

// check_attachment: a topic whose roles no package has never attaches.
check_attachment :: proc(d: ^Doctor, c: ^Ctx) {
	roles_in_use := make(map[string]bool, context.temp_allocator)
	for pk in c.pkgs {if pk.role_count == 1 {roles_in_use[pk.role] = true}}
	for t in c.rb.topics {
		attached := len(t.applies_to.roles) == 0
		for r in t.applies_to.roles {attached ||= roles_in_use[r]}
		if !attached {warn(d, "topic %s applies to roles %v but no package has one", t.name, t.applies_to.roles)}
	}
}

// odin_output returns stdout+stderr trimmed, "" if odin cannot run.
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
