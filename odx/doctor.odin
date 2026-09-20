package odx

import "core:fmt"
import "core:os"
import "core:strings"

// `odx doctor`: the toolchain and task-file drift report (sections 3, 17.11, 17.15).
// Errors exit 2: config broken, odin missing, a forbidden flag in use. Everything else is a
// warning, except version drift under --ci.

cmd_doctor :: proc(o: Opts) {
	p := must_load(o, true)
	errors, warnings := 0, 0
	warn :: proc(n: ^int, f: string, args: ..any) {
		n^ += 1
		fmt.print("warning: ")
		fmt.printfln(f, ..args)
	}
	err :: proc(n: ^int, f: string, args: ..any) {
		n^ += 1
		fmt.print("error: ")
		fmt.printfln(f, ..args)
	}

	exe := odin_exe(&p.cfg)
	version := odin_output(exe, "version")
	if version == "" {
		err(&errors, "cannot run %s (set odin.path in %s or ODX_ODIN)", exe, CONFIG_FILE)
	} else {
		_, _, ver := strings.partition(version, "version ")
		fmt.printfln("odin: %s %s", exe, ver)
		if want := p.cfg.odin.version; want != "" && !strings.has_prefix(ver, want) {
			if o.ci {err(&errors, "odin version %s does not match odin.version %s", ver, want)} else {warn(&warnings, "odin version %s does not match odin.version %s", ver, want)}
		}
		help := odin_output(exe, "help", "check")
		for f in p.cfg.odin.flags {
			name, _, _ := strings.partition(f, ":")
			if !strings.contains(
				   help,
				   strings.concatenate({"\n\t", name, "\n"}, context.temp_allocator),
			   ) &&
			   !strings.contains(
					   help,
					   strings.concatenate({"\n\t", name, ":"}, context.temp_allocator),
				   ) {
				err(&errors, "flag %s is not accepted by `odin check` on this compiler", f)
			}
		}
	}

	for f in p.cfg.odin.flags {
		if flag_listed(
			p.cfg.odin.forbidden_flags,
			f,
		) {err(&errors, "odin.flags contains forbidden flag %s", f)}
	}
	mise_path := join({p.root, "mise.toml"})
	if mise, rerr := os.read_entire_file(mise_path, context.allocator); rerr == nil {
		text := string(mise)
		for f in p.cfg.odin.forbidden_flags {
			if strings.contains(text, f) {err(&errors, "mise.toml uses forbidden flag %s", f)}
		}
		for f in p.cfg.odin.required_flags {
			if !strings.contains(
				text,
				f,
			) {warn(&warnings, "mise.toml test task lacks required flag %s", f)}
		}
	} else {
		warn(&warnings, "no mise.toml (odx init writes one)")
	}

	// the canonical test line, -vet-packages computed from the project's package names (17.15)
	names := make(map[string]bool, context.temp_allocator)
	for pk in load_packages(p.root, &p.cfg, package_dirs(p.root, &p.cfg)) {if pk.pkg != nil {names[pk.pkg.name] = true}}
	fmt.printfln(
		"expected test task: odin test . %s %s -vet-packages:%s",
		strings.join(p.cfg.odin.flags, " ", context.temp_allocator),
		strings.join(p.cfg.odin.required_flags, " ", context.temp_allocator),
		strings.join(sorted_keys(names), ",", context.temp_allocator),
	)

	for t in p.rb.topics {if t.overrides {warn(&warnings, "topic %s is overridden by %s", t.name, t.source)}}
	for id in sorted_keys(p.cfg.disabled) {fmt.printfln("disabled: %s (%s)", id, p.cfg.disabled[id])}

	fmt.printfln("%d errors, %d warnings", errors, warnings)
	if errors > 0 {os.exit(EXIT_TOOL)}
}

// odin_output runs odin with args and returns stdout+stderr trimmed, "" if it cannot run.
odin_output :: proc(exe: string, args: ..string) -> string {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, exe)
	append(&cmd, ..args)
	_, out, errb, err := os.process_exec({command = cmd[:]}, context.allocator)
	if err != nil {return ""}
	return strings.trim_space(strings.concatenate({string(out), string(errb)}))
}

// flag_listed: "-define:X=1" matches a listed "-define:X=1" or bare "-define".
flag_listed :: proc(list: []string, flag: string) -> bool {
	name, _, _ := strings.partition(flag, ":")
	for l in list {if l == flag || l == name {return true}}
	return false
}
