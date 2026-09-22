package policies

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Probe :: struct {
	bin, root, base: string,
	t:               ^testing.T,
}
Finding :: struct {
	rule, file, message: string,
}
Report :: struct {
	coverage:   struct {
		complete: bool,
		checks:   []struct {
			rule, status: string,
		},
	},
	violations: []Finding,
}
Case :: struct {
	name, rule: string,
	count:      int,
}

expect :: proc(p: ^Probe, ok: bool, name: string, loc := #caller_location) {
	testing.expect(p.t, ok, name, loc = loc)
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
check :: proc(p: ^Probe, name: string, expected: []string, scope := "") -> Report {
	args := make([dynamic]string)
	append(&args, "check", "--strict", "--json")
	if scope != "" {append(&args, scope)}
	output := run(p, name, 1 if len(expected) > 0 else 0, args[:])
	r: Report
	expect(p, json.unmarshal_string(output, &r) == nil, fmt.tprintf("%s report decodes", name))
	expect(p, r.coverage.complete, fmt.tprintf("%s evidence complete", name))
	expect(p, len(r.violations) == len(expected), fmt.tprintf("%s exact finding count", name))
	for id in expected {
		found := false
		for v in r.violations {if v.rule == id {found = true}}
		expect(p, found, fmt.tprintf("%s reports %s", name, id))
	}
	return r
}
copy_example :: proc(p: ^Probe, name: string) {
	p.root = fmt.tprintf("%s/%s", p.base, name)
	state, out, errors, err := os.process_exec(
		{command = {"cp", "-R", fmt.tprintf("examples/policies/%s", name), p.root}},
		context.allocator,
	)
	if err != nil ||
	   state.exit_code != 0 {panic(fmt.tprintf("copy example: %s %s %v", out, errors, err))}
}
guidance :: proc(p: ^Probe, ids: []string) {
	run(p, "write project guidance", 0, {"policy", "--write", "AGENTS.md"})
	run(p, "project guidance fresh", 0, {"policy", "--verify", "AGENTS.md"})
	text := read(p, "AGENTS.md")
	for id in ids {expect(p, strings.contains(text, fmt.tprintf("**%s**", id)), fmt.tprintf("guidance includes %s", id))}
	expect(
		p,
		strings.count(text, "\n- **") == len(ids),
		"guidance has exactly selected mechanical rules",
	)
}
cases :: proc(p: ^Probe, target: string, variants: []Case, replace: bool) {
	original := ""
	if replace {original = read(p, target)}
	for c in variants {
		write(p, target, read(p, fmt.tprintf("cases/%s.odin.txt", c.name)))
		expected := []string{}
		if c.rule != "" {
			expected = make([]string, max(c.count, 1))
			for &id in expected {id = c.rule}
		}
		check(p, c.name, expected)
	}
	if replace {write(p, target, original)} else {
		if err := os.remove(fmt.tprintf("%s/%s", p.root, target));
		   err != nil {panic(fmt.tprintf("%v", err))}
	}
}
audit_config :: proc(p: ^Probe, value: string, extra := "") {
	write(
		p,
		"odx.json5",
		strings.concatenate(
			{
				`{version:1,disabled:{"errors/R3":"No error convention"},odin:{flags:[],explicit_allocators:"off",`,
				value,
				extra,
				`}}`,
			},
		),
	)
}

@(test)
test_independent_policy_projects :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	base, err := os.make_directory_temp("", "odx-policies-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(base)
	bin, _ := filepath.abs("build/odx")
	p := Probe {
		t    = t,
		bin  = bin,
		base = base,
	}
	copy_example(&p, "minimal")
	r := check(&p, "minimal clean", {})
	for id in ([]string{"odx/feature-optout", "odx/vet-disable"}) {
		found := false
		for c in r.coverage.checks {if c.rule == id && c.status == "not_applicable" {found = true}}
		expect(&p, found, fmt.tprintf("disabled audit %s is not applicable", id))
	}
	guidance(&p, {"library/R1", "library/R2"})
	minimal_md := read(&p, "AGENTS.md")
	for text in ([]string{"### errors:", "### allocators:", "### dependencies:", "Reader checks for", "Reviewer advice scope:"}) {
		expect(
			&p,
			!strings.contains(minimal_md, text),
			fmt.tprintf("minimal guidance excludes %s", text),
		)
	}
	cases(
		&p,
		"parser/main.odin",
		{
			{"mutable", "library/R1", 1},
			{"conditional_mutable", "library/R1", 1},
			{"grouped_mutable", "library/R1", 1},
			{"foreign_import", "library/R2", 1},
			{"foreign_block", "library/R2", 2},
			{"conditional_foreign", "library/R2", 1},
			{"misleading_text", "", 0},
			{"file_tags", "", 0},
		},
		true,
	)
	config := read(&p, "odx.json5")
	disabled_config, _ := strings.replace_all(
		config,
		`"errors/R3":`,
		`"library/R1":"Temporarily disabled", "errors/R3":`,
	)
	write(&p, "odx.json5", disabled_config)
	write(&p, "parser/main.odin", read(&p, "cases/mutable.odin.txt"))
	check(&p, "disabled local rule is inactive in normal checks", {})

	write(&p, "odx.json5", config)
	write(&p, "parser/main.odin", read(&p, "cases/misleading_text.odin.txt"))
	write(
		&p,
		"support/main.odin",
		"package support\nforeign import libc \"system:c\"\nvalue :: 1\n",
	)
	write(
		&p,
		"parser/main.odin",
		"package parser\nimport \"../support\"\nvalue :: support.value\n",
	)
	check(&p, "direct foreign boundary scoped", {}, "parser")
	boundary := check(&p, "direct foreign boundary full", {"library/R2"})
	if len(boundary.violations) ==
	   1 {expect(&p, boundary.violations[0].file == "support/main.odin", "foreign report belongs to declaration package")}
	if err = os.remove_all(fmt.tprintf("%s/support", p.root));
	   err != nil {panic(fmt.tprintf("%v", err))}
	write(&p, "parser/main.odin", read(&p, "cases/misleading_text.odin.txt"))
	path := ".odx/topics/library/R1.odx.md"
	original := read(&p, path)
	write(
		&p,
		path,
		strings.concatenate({original, "\nReview this project's ownership boundary.\n"}),
	)
	before := read(&p, "AGENTS.md")
	run(&p, "local rule mutation stales guidance", 1, {"policy", "--verify", "AGENTS.md"})
	expect(&p, read(&p, "AGENTS.md") == before, "freshness check does not mutate guidance")
	run(&p, "regenerate changed local guidance", 0, {"policy", "--write", "AGENTS.md"})
	run(&p, "changed local guidance fresh", 0, {"policy", "--verify", "AGENTS.md"})
	write(&p, path, original)

	copy_example(&p, "strict")
	check(&p, "strict clean with adapter and app exemptions", {})
	guidance(
		&p,
		{"dependencies/R2", "dependencies/R3", "dependencies/R4", "errors/R3", "allocators/R1"},
	)
	cases(
		&p,
		"domain/case.odin",
		{
			{"mutable", "dependencies/R3", 1},
			{"foreign", "dependencies/R4", 1},
			{"error", "errors/R3", 1},
			{"allocator", "allocators/R1", 1},
			{"counterexamples", "", 0},
		},
		false,
	)
	cases(&p, "adapters/case.odin", {{"adapter-counterexamples", "", 0}}, false)
	write(&p, "domain/case.odin", read(&p, "cases/transitive.odin.txt"))
	full := check(&p, "strict transitive full", {"dependencies/R2"})
	scoped := check(&p, "strict transitive scoped", {"dependencies/R2"}, "domain")
	if len(full.violations) == 1 && len(scoped.violations) == 1 {
		a, b := full.violations[0], scoped.violations[0]
		expect(
			&p,
			a.rule == b.rule && a.file == b.file && a.message == b.message,
			"scoped dependency finding equals full finding",
		)
	}
	if err = os.remove(fmt.tprintf("%s/domain/case.odin", p.root));
	   err != nil {panic(fmt.tprintf("%v", err))}
	run(&p, "app scoped guidance", 0, {"policy", "--write", "APP.md", "app"})
	run(&p, "app scoped guidance fresh", 0, {"policy", "--verify", "APP.md", "app"})
	app := read(&p, "APP.md")
	expect(&p, strings.count(app, "\n- **") == 0, "app guidance has no domain mechanical rules")
	for id in ([]string{"dependencies/R2", "dependencies/R3", "dependencies/R4", "errors/R3", "allocators/R1"}) {
		expect(
			&p,
			!strings.contains(app, fmt.tprintf("**%s**", id)),
			fmt.tprintf("app guidance omits domain contract %s", id),
		)
	}


	p.root = fmt.tprintf("%s/audit", p.base)
	write(&p, "sample/main.odin", "#+feature using-stmt\n#+vet !tabs\npackage sample\n")
	audit_config(&p, "audit_file_tags:false,")
	check(&p, "audit opt out", {})
	run(&p, "audit off guidance", 0, {"policy", "--write", "AGENTS.md"})
	audit_config(&p, "")
	run(&p, "audit setting change stales guidance", 1, {"policy", "--verify", "AGENTS.md"})
	check(&p, "audit defaults retained", {"odx/feature-optout", "odx/vet-disable"})
	for value in ([]string{"null", "0", `"false"`}) {
		audit_config(&p, fmt.tprintf("audit_file_tags:%s,", value))
		run(&p, "invalid audit boolean rejected", 2, {"check", "--fast"})
	}
	write(&p, "sample/main.odin", "package sample\n")
	audit_config(&p, "audit_file_tags:false,", `allowed_vet_disables:["tabs"]`)
	check(&p, "audit opt out suppresses stale allowlist", {})
	audit_config(&p, "audit_file_tags:true,", `allowed_vet_disables:["tabs"]`)
	check(&p, "enabled audit detects stale allowlist", {"odx/stale-config-entry"})
}
