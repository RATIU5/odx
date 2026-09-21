package odx

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// odx.baseline: pre-existing violations frozen by semantic key so a
// project with debt can adopt odx without every edit blocking. Softens, never hides: a
// baselined violation still prints and appears in --json, it just stops failing the build.
// Shrinks automatically on a full run; grows only through `odx baseline add | regen`.
// Never keyed on line numbers or line text: both break on `odin fmt` and renames.

BASELINE_FILE :: "odx.baseline"
BASELINE_HEAD :: "format_version: 1"

Baseline_Entry :: struct {
	rule, pkg, subject, reason: string,
	hit:                        bool,
}

baseline_key :: proc(v: Violation) -> (rule, pkg, subject: string, ok: bool) {
	if v.subject == "" || v.baselined {return}
	pkg = dir_of(v.file) if strings.has_suffix(v.file, ".odin") else v.file
	if pkg == "" {pkg = "."}
	return v.rule, pkg, v.subject, true
}

read_baseline :: proc(root: string) -> (out: [dynamic]Baseline_Entry, exists: bool) {
	data, err := os.read_entire_file(join({root, BASELINE_FILE}), context.allocator)
	if err != nil {return}
	exists = true
	for line in strings.split_lines(string(data), context.temp_allocator) {
		if line == "" || line == BASELINE_HEAD {continue}
		body, _, reason := strings.partition(line, "#")
		f := strings.split(strings.trim_right_space(body), "\t", context.temp_allocator)
		if len(f) != 3 {continue} 	// ponytail: a malformed line is dropped on the next rewrite
		append(&out, Baseline_Entry{f[0], f[1], f[2], strings.trim_space(reason), false})
	}
	return
}

write_baseline :: proc(root: string, es: []Baseline_Entry) {
	lines := make([dynamic]string, context.temp_allocator)
	for e in es {
		l := fmt.tprintf("%s\t%s\t%s", e.rule, e.pkg, e.subject)
		if e.reason != "" {l = fmt.tprintf("%s  # %s", l, e.reason)}
		append(&lines, l)
	}
	slice.sort(lines[:])
	write_atomic(
		join({root, BASELINE_FILE}),
		fmt.tprintf("%s\n%s\n", BASELINE_HEAD, strings.join(lines[:], "\n")),
	)
}

// apply_baseline marks listed violations and, on a full non-CI run, drops entries nothing hit.
apply_baseline :: proc(c: ^Ctx, full, ci: bool) {
	es, exists := read_baseline(c.root)
	if !exists {return}
	for &v in c.r.violations {
		rule, pkg, subject, ok := baseline_key(v)
		if !ok {continue}
		if r := find_rule(c.rb, rule); r == nil || !r.baselineable {continue}
		for &e in es {
			if e.rule == rule && e.pkg == pkg && e.subject == subject {
				e.hit = true
				v.baselined = true
			}
		}
	}
	if !full {return} 	// --fast, --topic or a narrowed path would report false shrinkage
	live := make([dynamic]Baseline_Entry)
	for e in es {if e.hit {append(&live, e)}}
	if len(live) == len(es) {return}
	if ci {
		tool_error(
			c.r,
			"%s lists %d entries that no longer fire; run `odx check` (not --ci) to shrink it",
			BASELINE_FILE,
			len(es) - len(live),
		)
		return
	}
	write_baseline(c.root, live[:])
}

// cmd_baseline: `add` appends every current unbaselined violation with a subject; `regen`
// rewrites from scratch.
cmd_baseline :: proc(o: Opts) {
	if len(o.args) != 1 ||
	   (o.args[0] != "add" && o.args[0] != "regen") {fail("usage: odx baseline add | regen")}
	p := must_load(o, true)
	c := make_ctx(&p, nil)
	if o.args[0] == "regen" {os.remove(join({p.root, BASELINE_FILE}))} 	// never read the file being rewritten
	run_checks(&c, Opts{})
	es, _ := read_baseline(p.root)
	added := 0
	for v in c.r.violations {
		rule, pkg, subject, ok := baseline_key(v)
		if !ok {continue}
		if r := find_rule(c.rb, rule); r == nil || !r.baselineable {continue}
		dup := false
		for e in es {dup ||= e.rule == rule && e.pkg == pkg && e.subject == subject}
		if dup {continue}
		append(&es, Baseline_Entry{rule, pkg, subject, "", true})
		added += 1
	}
	write_baseline(p.root, es[:])
	fmt.printfln("%s: %d entries (%d added)", BASELINE_FILE, len(es), added)
}

write_atomic :: proc(path, text: string) {
	tmp := strings.concatenate({path, ".tmp"}, context.temp_allocator)
	if err := os.write_entire_file(tmp, text); err != nil {fail("write %s: %v", tmp, err)}
	if err := os.rename(tmp, path); err != nil {fail("rename %s: %v", path, err)}
}
