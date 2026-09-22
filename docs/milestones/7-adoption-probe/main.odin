package milestone_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Probe :: struct {
	bin, root:      string,
	passed, failed: int,
}
Report :: struct {
	schema:      int,
	coverage:    struct {
		complete: bool,
	},
	violations:  []struct {
		rule, severity:      string,
		baselined, blocking: bool,
	},
	tool_errors: []string,
	summary:     struct {
		errors, warnings, ignored, baselined, omitted: int,
	},
}

expect :: proc(p: ^Probe, ok: bool, name: string) {
	if ok {p.passed += 1} else {p.failed += 1}
	fmt.printfln("%s %s", "PASS" if ok else "FAIL", name)
}
write :: proc(p: ^Probe, path, contents: string) {
	full := fmt.tprintf("%s/%s", p.root, path)
	err := os.make_directory_all(filepath.dir(full))
	if err != nil && err != os.General_Error.Exist {panic(fmt.tprintf("%v", err))}
	if err = os.write_entire_file(full, contents); err != nil {panic(fmt.tprintf("%v", err))}
}
read :: proc(p: ^Probe, path: string) -> string {
	data, err := os.read_entire_file(fmt.tprintf("%s/%s", p.root, path), context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	return string(data)
}
run :: proc(p: ^Probe, name: string, code: int, args: []string, compiler := "") -> string {
	cmd := make([dynamic]string)
	append(&cmd, p.bin)
	append(&cmd, ..args)
	append(&cmd, "--root", p.root)
	env: [dynamic]string
	if compiler != "" {
		inherited, err := os.environ(context.allocator)
		if err != nil {panic(fmt.tprintf("%v", err))}
		for entry in inherited {if !strings.has_prefix(entry, "ODX_ODIN=") {append(&env, entry)}}
		append(&env, fmt.tprintf("ODX_ODIN=%s", compiler))
	}
	state, out, errors, err := os.process_exec({command = cmd[:], env = env[:]}, context.allocator)
	expect(
		p,
		err == nil && state.exit_code == code,
		fmt.tprintf("%s exit %d (got %d)", name, code, state.exit_code),
	)
	if err != nil || state.exit_code != code {fmt.printfln("%s\n%s", out, errors)}
	return string(out)
}
report :: proc(p: ^Probe, name: string, code: int, args: []string, compiler := "") -> Report {
	out := run(p, name, code, args, compiler)
	r: Report
	expect(
		p,
		json.unmarshal_string(out, &r) == nil && r.schema == 1,
		fmt.tprintf("%s schema 1 JSON report", name),
	)
	return r
}
has :: proc(r: Report, rule: string) -> bool {
	for v in r.violations {if v.rule == rule {return true}}
	return false
}

main :: proc() {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-m7-adoption-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(root)
	bin := os.get_env("ODX_PROBE_BIN", context.allocator)
	if bin == "" {bin, _ = filepath.abs("build/odx")}
	p := Probe {
		bin  = bin,
		root = root,
	}
	config :: `{version:1,disabled:{"errors/R3":"No error convention"},odin:{explicit_allocators:"off",audit_file_tags:false}}`
	write(&p, "odx.json5", config)
	write(
		&p,
		".odx/topics/adoption/topic.md",
		"---\nname:\"adoption\",summary:\"Gradual adoption probe\",\n---\nLocal source policy.\n",
	)
	write(
		&p,
		".odx/topics/adoption/R1.odx.md",
		`---
id:"R1",statement:"No package variables",why:"Caller-owned state",instead_of:"Shared state",evidence:"Native syntax",cost:"Explicit state passing",severity:"warning",check:{kind:"pattern",match:"decl",at:"package_scope",mutable:true},
---
No package-scope mutable declarations.
`,
	)
	write(&p, "lib/old.odin", "package lib\nold: int\n")
	r := report(&p, "warning advisory", 0, {"check", "--json"})
	expect(
		&p,
		r.coverage.complete && r.summary.warnings == 1 && r.summary.errors == 0,
		"advisory warning has complete source evidence",
	)
	r = report(&p, "warning strict", 1, {"check", "--json", "--strict"})
	expect(
		&p,
		len(r.violations) == 1 &&
		r.violations[0].severity == "warning" &&
		r.violations[0].blocking,
		"strict preserves warning severity and compatibility blocking field",
	)
	run(&p, "freeze old warning", 0, {"baseline", "regen"})
	r = report(&p, "baselined warning strict", 0, {"check", "--json", "--strict"})
	expect(
		&p,
		r.summary.baselined == 1 &&
		r.summary.warnings == 0 &&
		len(r.violations) == 1 &&
		r.violations[0].baselined,
		"accepted warning remains visible without failing strict",
	)
	write(&p, "lib/new.odin", "package lib\nnew: int\nnewer: int\n")
	r = report(&p, "new warnings advisory", 0, {"check", "--json"})
	expect(
		&p,
		r.summary.baselined == 1 && r.summary.warnings == 2,
		"new source does not inherit old warning acceptance",
	)
	r = report(
		&p,
		"new warnings strict truncated",
		1,
		{"check", "--json", "--strict", "--max-violations", "1"},
	)
	expect(
		&p,
		r.summary.warnings == 2 &&
		r.summary.baselined == 1 &&
		r.summary.omitted == 2 &&
		len(r.violations) == 1,
		"truncation preserves all exit counts",
	)
	baseline := read(&p, "odx.baseline")
	r = report(
		&p,
		"unrelated warnings do not fail ignore audit",
		0,
		{"ignores", "--stale", "--json"},
	)
	expect(
		&p,
		r.coverage.complete && r.summary.warnings == 3 && r.summary.baselined == 0,
		"ignore audit exposes unsoftened unrelated findings",
	)
	write(
		&p,
		"lib/new.odin",
		"package lib\n// odx:ignore adoption/R1 reason: Required for compatibility\nnew: int\n",
	)
	r = report(&p, "reasoned suppression", 0, {"check", "--json", "--strict"})
	expect(
		&p,
		r.summary.ignored == 1 && r.summary.baselined == 1,
		"suppression removes new warning while old warning remains baselined",
	)
	write(
		&p,
		"lib/old.odin",
		"package lib\n// odx:ignore adoption/R1 reason: Required for compatibility\nold: int\n",
	)
	r = report(&p, "ignore audit skips stale baseline", 0, {"ignores", "--stale", "--json"})
	expect(
		&p,
		r.coverage.complete && r.summary.ignored == 2 && len(r.tool_errors) == 0,
		"baseline state does not invalidate suppression audit",
	)
	expect(&p, read(&p, "odx.baseline") == baseline, "JSON ignore audit preserves baseline bytes")
	run(&p, "text ignore audit", 0, {"ignores", "--stale"})
	expect(&p, read(&p, "odx.baseline") == baseline, "text ignore audit preserves baseline bytes")
	write(
		&p,
		"lib/new.odin",
		"package lib\n// odx:ignore adoption/R1 Required for compatibility\nnew: int\n",
	)
	r = report(&p, "missing reason marker", 1, {"ignores", "--stale", "--json"})
	expect(
		&p,
		has(r, "odx/bad-ignore") && has(r, "adoption/R1") && r.coverage.complete,
		"malformed directive cannot suppress warning",
	)
	write(
		&p,
		"lib/new.odin",
		"package lib\n// odx:ignore adoption/R1 reason: Required for compatibility\nnew :: 1\n",
	)
	r = report(&p, "stale suppression", 1, {"ignores", "--stale", "--json"})
	expect(
		&p,
		has(r, "odx/stale-ignore") && r.coverage.complete,
		"resolved declaration makes suppression stale",
	)
	text := run(&p, "text stale suppression", 1, {"ignores", "--stale"})
	expect(
		&p,
		strings.contains(text, "odx/stale-ignore"),
		"text audit identifies stale suppression",
	)
	write(
		&p,
		"lib/new.odin",
		"package lib\n// odx:ignore adoption/R1 reason: Required for compatibility\nnew: proc(\n",
	)
	r = report(&p, "failed source ignore audit", 2, {"ignores", "--stale", "--json"})
	expect(
		&p,
		!r.coverage.complete && has(r, "odin/syntax") && !has(r, "odx/stale-ignore"),
		"parse failure is visible and cannot certify stale suppression",
	)
	text = run(&p, "text failed source audit", 2, {"ignores", "--stale"})
	expect(&p, strings.contains(text, "odin/syntax"), "text audit exposes syntax failure")
	expect(&p, read(&p, "odx.baseline") == baseline, "failed audits preserve baseline bytes")
	write(&p, "lib/new.odin", "package lib\nnew :: 1\n")
	write(&p, "odx.json5", `{version:1,odin:{explicit_allocators:"off",audit_file_tags:false}}`)
	r = report(
		&p,
		"unavailable compiler ignore audit",
		2,
		{"ignores", "--stale", "--json"},
		fmt.tprintf("%s/missing-odin", p.root),
	)
	expect(
		&p,
		!r.coverage.complete && len(r.tool_errors) > 0,
		"unavailable compiler produces structured audit failure",
	)
	expect(
		&p,
		read(&p, "odx.baseline") == baseline,
		"unavailable compiler audit preserves baseline bytes",
	)
	fmt.printfln("milestone 7 adoption: %d passed, %d failed", p.passed, p.failed)
	if p.failed > 0 {os.exit(1)}
}
