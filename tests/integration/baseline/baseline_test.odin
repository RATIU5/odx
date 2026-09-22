package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Probe :: struct {
	t: ^testing.T,
	bin, root, base: string,
	passed, failed:  int,
}
Finding :: struct {
	rule, file, message: string,
	baselined:           bool,
}
Report :: struct {
	coverage:   struct {
		complete: bool,
		checks:   []struct {
			rule, status: string,
		},
	},
	violations: []Finding,
	summary:    struct {
		errors, baselined: int,
	},
}
expect :: proc(p: ^Probe, ok: bool, name: string) {
	testing.expect(p.t, ok, name)
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
	if err != nil {panic(fmt.tprintf("%s: %v", path, err))}
	return string(data)
}
run :: proc(p: ^Probe, name: string, code: int, args: []string) -> string {
	cmd := make([dynamic]string)
	append(&cmd, p.bin)
	append(&cmd, ..args)
	append(&cmd, "--root", p.root)
	state, out, errors, err := os.process_exec({command = cmd[:]}, context.allocator)
	expect(
		p,
		err == nil && state.exit_code == code,
		fmt.tprintf("%s exit %d (got %d)", name, code, state.exit_code),
	)
	if err != nil || state.exit_code != code {fmt.printfln("%s\n%s", out, errors)}
	return string(out)
}

replace :: proc(s, old, new: string) -> string {
	result, _ := strings.replace_all(s, old, new)
	return result
}
Document :: struct {
	format_version: int,
	entries:        []Entry,
}
Entry :: struct {
	rule, file, subject, fingerprint: string,
	line, col:                        int,
	reason:                           string,
}
CONFIG :: `{
 version:1, exclude:[".odx/**"],
 disabled:{"errors/R3":"Adoption fixture uses only local source rules."},
 odin:{explicit_allocators:"off",audit_file_tags:false},
}`
SOURCE :: "package sample\nimport \"core:fmt\"\nRun :: proc() {\n\tfmt.println(\"old\")\n}\n"
rule :: proc(p: ^Probe, id, check: string, eligibility := "") {
	write(
		p,
		fmt.tprintf(".odx/topics/local/%s.odx.md", id),
		fmt.tprintf(
			`---
id: "%s",
statement: "Avoid selected syntax.", why: "Adopt local restrictions gradually.",
instead_of: "Existing syntax.", evidence: "Native AST selector.", cost: "Caller refactors.",
severity: "error", %s
check: %s,
---
Project-owned adoption rule.
`,
			id,
			eligibility,
			check,
		),
	)
}
document :: proc(p: ^Probe) -> Document {
	d: Document
	if err := json.unmarshal_string(read(p, "odx.baseline"), &d);
	   err != nil {panic(fmt.tprintf("%v", err))}
	return d
}
save :: proc(p: ^Probe, d: Document) {
	data, err := json.marshal(d)
	if err != nil {panic(fmt.tprintf("%v", err))}
	write(p, "odx.baseline", string(data))
}
check :: proc(p: ^Probe, name: string, code, accepted, errors: int, args: []string = nil) {
	commands := make([dynamic]string)
	append(&commands, "check", "--json")
	append(&commands, ..args)
	before := read(p, "odx.baseline")
	output := run(p, name, code, commands[:])
	r: Report
	expect(p, json.unmarshal_string(output, &r) == nil, fmt.tprintf("%s report decodes", name))
	expect(
		p,
		r.summary.baselined == accepted,
		fmt.tprintf("%s accepted count %d (got %d)", name, accepted, r.summary.baselined),
	)
	expect(
		p,
		r.summary.errors == errors,
		fmt.tprintf("%s new errors %d (got %d)", name, errors, r.summary.errors),
	)
	expect(p, read(p, "odx.baseline") == before, fmt.tprintf("%s never mutates baseline", name))
}
@(test)
test_baseline :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	base, err := os.make_directory_temp("", "odx-baseline-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(base)
	bin := os.get_env("ODX_BASELINE_BIN", context.allocator)
	if bin == "" {bin, _ = filepath.abs("build/odx")}
	p := Probe {
		t = t,
		bin  = bin,
		root = base,
		base = base,
	}
	write(&p, "odx.json5", CONFIG)
	write(
		&p,
		".odx/topics/local/topic.md",
		"---\nname: \"local\", summary: \"Local adoption checks.\",\n---\nAdopt source checks incrementally.\n",
	)
	rule(&p, "R1", `{kind:"pattern",match:"import",name:"core:fmt"}`)
	rule(&p, "R2", `{kind:"pattern",match:"call",names:["fmt.println"]}`)
	write(&p, "sample/a.odin", SOURCE)
	run(&p, "accept original debt", 0, {"baseline", "regen"})
	d := document(&p)
	expect(&p, d.format_version == 2 && len(d.entries) == 2, "version 2 stores both occurrences")
	check(&p, "accepted debt visible", 0, 2, 0)
	check(&p, "accepted debt strict CI", 0, 2, 0, {"--strict", "--ci"})
	original := read(&p, "odx.baseline")
	run(&p, "regen deterministic", 0, {"baseline", "regen"})
	expect(&p, read(&p, "odx.baseline") == original, "equivalent regen bytes")
	d = document(&p); d.entries[0].reason = "tracked #7\nkeep\tthis reason"; save(&p, d)
	reason := d.entries[0].reason
	write(&p, "sample/b.odin", replace(SOURCE, "Run ::", "Other ::"))
	check(&p, "same-package new import and call", 1, 2, 2, {"--ci"})
	run(&p, "add new file debt", 0, {"baseline", "add"})
	d = document(
		&p,
	); expect(&p, len(d.entries) == 4 && d.entries[0].reason == reason, "add retains reasons and distinct entries")
	check(&p, "all accepted", 0, 4, 0)
	write(&p, "sample/b.odin", "package sample\n")
	check(&p, "ordinary stale check read only", 2, 2, 0)
	check(&p, "CI stale check read only", 2, 2, 0, {"--ci"})
	check(&p, "fast cannot judge stale debt", 0, 2, 0, {"--fast"})
	check(&p, "topic cannot judge stale debt", 0, 2, 0, {"--topic", "local"})
	check(&p, "path cannot judge stale debt", 0, 2, 0, {"sample"})
	run(&p, "add preserves stale entries", 0, {"baseline", "add"})
	expect(&p, len(document(&p).entries) == 4, "add does not prune")
	run(&p, "explicit prune", 0, {"baseline", "prune"})
	d = document(
		&p,
	); expect(&p, len(d.entries) == 2 && d.entries[0].reason == reason, "prune removes only resolved and preserves reason")
	for name, i in ([]string{"new repeated call", "renamed enclosing procedure", "line shift", "changed argument"}) {
		changed := replace(
			SOURCE,
			"\tfmt.println(\"old\")",
			"\tfmt.println(\"old\")\n\tfmt.println(\"new\")",
		)
		expected := 3
		if i == 1 {changed = replace(SOURCE, "Run ::", "Renamed ::"); expected = 2}
		if i == 2 {changed = strings.concatenate({"\n", SOURCE}); expected = 2}
		if i == 3 {changed = replace(SOURCE, "old", "new"); expected = 2}
		write(&p, "sample/a.odin", changed)
		check(&p, name, 2, 0, expected, {"--ci"})
		run(&p, "prune does not accept changed debt", 0, {"baseline", "prune"})
		expect(&p, len(document(&p).entries) == 0, "changed snapshot fully reopened")
		write(&p, "sample/a.odin", SOURCE)
		run(&p, "restore acceptance", 0, {"baseline", "regen"})
	}
	before := read(&p, "odx.baseline")
	for broken in ([]string{"package sample\nInvalid: \n", "package sample\nInvalid :: proc() { missing() }\n"}) {
		write(&p, "sample/a.odin", broken)
		run(&p, "failed source check", 1, {"check", "--json"})
		expect(&p, read(&p, "odx.baseline") == before, "failed check retains debt")
		for action in ([]string{"add", "prune", "regen"}) {
			run(&p, "failed analysis refuses write", 2, {"baseline", action})
			expect(&p, read(&p, "odx.baseline") == before, "failed write preserves bytes")
		}
	}
	write(&p, "sample/a.odin", SOURCE)
	compiler := os.get_env("ODX_ODIN", context.allocator)
	expect(
		&p,
		os.set_env("ODX_ODIN", "/missing/odx-baseline-compiler") == nil,
		"set unavailable compiler",
	)
	before = read(&p, "odx.baseline")
	for args in ([][]string{{"check", "--json"}, {"baseline", "add"}, {"baseline", "prune"}, {"baseline", "regen"}}) {
		run(&p, "unavailable compiler fails closed", 2, args)
		expect(&p, read(&p, "odx.baseline") == before, "unavailable compiler preserves debt")
	}
	if compiler ==
	   "" {os.unset_env("ODX_ODIN")} else {expect(&p, os.set_env("ODX_ODIN", compiler) == nil, "restore compiler")}
	// No-change incremental checks still validate baseline syntax, without pruning.
	for args in ([][]string{{"init", "-q"}, {"add", "."}, {"-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"}}) {
		command := make([dynamic]string)
		append(&command, "git", "-C", p.root)
		append(&command, ..args)
		state, _, _, git_error := os.process_exec({command = command[:]}, context.allocator)
		expect(&p, git_error == nil && state.exit_code == 0, "initialize incremental fixture")
	}
	check(&p, "no-change since preserves baseline", 0, 0, 0, {"--since", "HEAD"})
	write(&p, "odx.baseline", "malformed")
	run(&p, "no-change since rejects invalid baseline", 2, {"check", "--since", "HEAD", "--json"})
	expect(
		&p,
		read(&p, "odx.baseline") == "malformed",
		"no-change validation preserves invalid bytes",
	)
	write(&p, "odx.baseline", before)
	for malformed in ([]string{"format_version: 1\nlocal/R1\tsample\tcore:fmt\n", `{"format_version":99,"entries":[]}`, `{"format_version":2,"entries":[{}]}`, "{"}) {
		write(&p, "odx.baseline", malformed)
		for args in ([][]string{{"check", "--json"}, {"baseline", "add"}, {"baseline", "prune"}}) {
			run(&p, "invalid baseline refuses normal use", 2, args)
			expect(&p, read(&p, "odx.baseline") == malformed, "invalid file preserved")
		}
		run(&p, "explicit regen replaces invalid or legacy", 0, {"baseline", "regen"})
		expect(
			&p,
			len(document(&p).entries) == 2,
			"explicit replacement accepts current occurrences",
		)
	}
	// Each duplicate entry can match at most one occurrence; extra acceptance is stale.
	d = document(&p)
	copies := make([]Entry, 3); copy(copies, d.entries); copies[2] = d.entries[0]
	save(&p, Document{2, copies})
	check(&p, "duplicate entry has bounded multiplicity", 2, 2, 0)
	run(&p, "prune duplicate surplus", 0, {"baseline", "prune"})
	expect(&p, len(document(&p).entries) == 2, "prune unused duplicate")
	rule(&p, "R2", `{kind:"pattern",match:"call",names:["fmt.println"]}`, "baselineable:false,")
	run(&p, "ineligible rule regeneration", 0, {"baseline", "regen"})
	expect(&p, len(document(&p).entries) == 1, "baselineable false excludes entry")
	check(&p, "ineligible debt still blocks", 1, 1, 1)
	baseline_path := fmt.tprintf("%s/odx.baseline", p.root)
	before = read(&p, "odx.baseline")
	expect(&p, os.chmod(baseline_path, {}) == nil, "restrict fixture baseline permissions")
	_, access_error := os.read_entire_file(baseline_path, context.allocator)
	if access_error != nil {
		for args in ([][]string{{"check", "--json"}, {"baseline", "add"}, {"baseline", "prune"}, {"baseline", "regen"}}) {
			run(&p, "unreadable baseline refused", 2, args)
		}
	} else {fmt.println("SKIP unreadable-file fixture: process can bypass file permissions")}
	expect(
		&p,
		os.chmod(baseline_path, {.Read_User, .Write_User}) == nil,
		"restore fixture permissions",
	)
	expect(&p, read(&p, "odx.baseline") == before, "unreadable file retains bytes")
	// Never replace a baseline symlink or its target, even on explicit regen.
	before = read(&p, "odx.baseline")
	write(&p, "target", before)
	expect(&p, os.remove(fmt.tprintf("%s/odx.baseline", p.root)) == nil, "remove fixture baseline")
	state, _, _, link_error := os.process_exec(
		{command = {"ln", "-s", "target", fmt.tprintf("%s/odx.baseline", p.root)}},
		context.allocator,
	)
	expect(&p, link_error == nil && state.exit_code == 0, "create fixture symlink")
	for args in ([][]string{{"check", "--json"}, {"baseline", "add"}, {"baseline", "prune"}, {"baseline", "regen"}}) {
		run(&p, "symlink baseline refused", 2, args)
		info, stat_error := os.lstat(fmt.tprintf("%s/odx.baseline", p.root), context.allocator)
		expect(&p, stat_error == nil && info.type == .Symlink, "symlink preserved")
		expect(&p, read(&p, "target") == before, "symlink target preserved")
	}
	fmt.printfln("%d assertions passed; %d failed", p.passed, p.failed)
	testing.expect_value(t, p.failed, 0)
}
