package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Family A: `odin check <pkg> -json-errors` per project package, re-emitted with rule ids.

Odin_Errors :: struct {
	error_count: int,
	errors:      []struct {
		type: string,
		pos:  struct {
			file:                             string,
			offset, line, column, end_column: int,
		},
		msgs: []string,
	},
}

odin_exe :: proc(cfg: ^Config) -> string {
	if p := os.get_env("ODX_ODIN", context.allocator); p != "" {return p}
	if cfg.odin.path != "" {return cfg.odin.path}
	return "odin"
}

// odin_flags: config flags plus the derived -vet-packages / -collection / -custom-attribute.
odin_flags :: proc(c: ^Ctx) -> []string {
	out := make([dynamic]string)
	append(&out, ..c.cfg.odin.flags)
	names := make(map[string]bool, context.temp_allocator)
	for p in c.pkgs {if p.pkg != nil {names[p.pkg.name] = true}}
	if len(names) > 0 {
		append(
			&out,
			fmt.aprintf(
				"-vet-packages:%s",
				strings.join(sorted_keys(names), ",", context.temp_allocator),
			),
		)
	}
	for k in sorted_keys(c.cfg.odin.collections) {
		append(
			&out,
			fmt.aprintf("-collection:%s=%s", k, join({c.root, c.cfg.odin.collections[k]})),
		)
	}
	for a in c.cfg.odin.custom_attributes {append(&out, fmt.aprintf("-custom-attribute:%s", a))}
	return out[:]
}

// run_odin: ok is false when odin could not be started at all.
run_odin :: proc(c: ^Ctx, args: ..string) -> (exit_code: int, stderr: string, ok: bool) {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, odin_exe(c.cfg))
	append(&cmd, ..args)
	state, _, err_bytes, err := os.process_exec({command = cmd[:]}, context.allocator)
	if err != nil {
		tool_error(c.r, "cannot run %s: %v", cmd[0], err)
		return
	}
	return state.exit_code, strings.trim_space(string(err_bytes)), true
}

run_family_a :: proc(c: ^Ctx) {
	flags := odin_flags(c)
	for &p in c.pkgs {
		if p.pkg == nil || len(p.diags) > 0 {continue} 	// the parser already reported it
		args := make([dynamic]string, context.temp_allocator)
		append(&args, "check", p.dir)
		append(&args, ..flags)
		append(&args, "-no-entry-point", "-json-errors")
		code: int
		text: string
		ok: bool
		for _ in 0 ..< 3 {
			code, text, ok = run_odin(c, ..args[:])
			// ponytail: the 2026-09 nightly segfaults intermittently (exit 11, no output): retry
			if !(ok && code != 0 && text == "") {break}
		}
		if !ok {return}
		if text == "" {
			if code != 0 {tool_error(c.r, "odin check %s exited %d with no output", p.rel, code)}
			continue
		}
		oe: Odin_Errors
		if uerr := json.unmarshal_string(text, &oe); uerr != nil {
			tool_error(c.r, "odin check %s: unparseable -json-errors output: %s", p.rel, text)
			continue
		}
		// odin type-checks dependencies too; each package reports only its own files, and a
		// broken dependency becomes one summary line so the failure is never silent.
		foreign_errors := 0
		seen := make(map[string]bool, context.temp_allocator) // odin repeats some diagnostics
		for e in oe.errors {
			key := fmt.tprintf("%s:%d:%d:%s", e.pos.file, e.pos.line, e.pos.column, e.msgs)
			if key in seen {continue}
			seen[key] = true
			file, _ := rel_of(c.root, e.pos.file)
			if dir, _ := rel_of(c.root, filepath.dir(e.pos.file)); dir != p.rel {
				if e.type == "error" {foreign_errors += 1}
				continue
			}
			rule, msg := classify_odin_message(
				c,
				e.type,
				strings.join(e.msgs, " ", context.temp_allocator),
			)
			// odin sometimes reports column 0 (ols clamps too)
			note(c.r, rule, "odin", file, max(e.pos.line, 1), max(e.pos.column, 1), msg)
			if e.type != "error" {c.r.violations[len(c.r.violations) - 1].severity = .warning}
		}
		if foreign_errors > 0 {
			note(
				c.r,
				"odin/error",
				"odin",
				p.rel if p.rel != "" else ".",
				1,
				1,
				fmt.aprintf(
					"a dependency fails to type-check (%d errors outside this package); run `odx check` on it",
					foreign_errors,
				),
			)
		}
	}
}

// classify_odin_message maps a compiler diagnostic to a rule id: `@(deprecated="<topic>/<R>: …")`
// re-emits under that rule, everything else is odin/error or odin/warning.
classify_odin_message :: proc(c: ^Ctx, type, msg: string) -> (rule, out: string) {
	rule = "odin/error" if type == "error" else "odin/warning"
	out = strings.join(strings.fields(msg, context.temp_allocator), " ") // collapse the tabbed follow-up notes
	if i := strings.index(out, "is deprecated: "); i >= 0 {
		if id, _, tail := strings.partition(out[i + len("is deprecated: "):], ": ");
		   tail != "" && find_rule(c.rb, id) != nil {
			return id, tail
		}
	}
	return
}
