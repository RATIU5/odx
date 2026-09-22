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
Report :: struct {
	violations: []struct {
		file, rule, subject: string,
	},
	coverage:   struct {
		checks: []struct {
			package_dir, rule, status: string,
		},
	},
}
CONFIG :: `{version:1,roles:{domain:["sample"]},odin:{explicit_allocators:"off"}}`
SOURCE :: `package sample
import "core:fmt"
Ctx :: struct {}
constant :: 42
state: int
alpha :: proc(ctx: ^Ctx) {}
beta :: proc() {}
@(private)
hidden :: proc() {}
grouped :: proc(a, b: ^Ctx) {}
exercise :: proc() {fmt.println("hello")}
foreign import libc "system:c"
foreign libc {
    getchar :: proc() -> i32 ---
}
`

write :: proc(path, contents: string) {
	err := os.make_directory_all(filepath.dir(path))
	if err != nil && err != os.General_Error.Exist {panic(fmt.tprintf("%v", err))}
	if err = os.write_entire_file(path, contents); err != nil {panic(fmt.tprintf("%v", err))}
}
source :: proc(p: ^Probe, path, contents: string) {write(
		fmt.tprintf("%s/%s", p.root, path),
		contents,
	)}
expect :: proc(p: ^Probe, ok: bool, name: string) {
	testing.expect(p.t, ok, name)
	if ok {p.passed += 1} else {p.failed += 1}
	fmt.printfln("%s %s", "PASS" if ok else "FAIL", name)
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
		fmt.tprintf("%s: exit %d (got %d)", name, code, state.exit_code),
	)
	if err != nil || state.exit_code != code {fmt.printfln("%s\n%s", out, errors)}
	return string(out)
}
trial :: proc(p: ^Probe, name, spec: string, count: int) {
	out := run(p, name, 0, {"rule", "try", spec, "--count"})
	expect(
		p,
		strings.trim_space(out) == fmt.tprintf("%d match%s", count, "" if count == 1 else "es"),
		fmt.tprintf("%s: %d matches", name, count),
	)
}
check :: proc(p: ^Probe, name: string, code: int) -> Report {
	out := run(p, name, code, {"check", "--fast", "--json"})
	r: Report
	expect(p, json.unmarshal_string(out, &r) == nil, fmt.tprintf("%s: valid report", name))
	return r
}
count_rule :: proc(r: Report, id: string) -> int {
	n := 0
	for v in r.violations {if v.rule == id {n += 1}}
	return n
}
status :: proc(r: Report, id: string) -> string {
	for c in r.coverage.checks {if c.rule == id {return c.status}}
	return "absent"
}
topic :: proc(p: ^Probe, name: string) {
	source(
		p,
		fmt.tprintf(".odx/topics/%s/topic.md", name),
		fmt.tprintf(
			"---\nname:%q,\nsummary:\"Local policy\",\napplies_to:{{roles:[\"unrelated\"]}},\n---\nLocal reader context.\n",
			name,
		),
	)
}
rule_text :: proc(id, spec: string) -> string {
	return fmt.tprintf(
		"---\nid:%q,\nstatement:\"Project policy marker %s\",\nwhy:\"Enforce this project's convention\",\ninstead_of:\"Unrestricted source\",\nevidence:\"Compiler-valid integration test\",\ncost:\"Intentional source restriction\",\nseverity:\"error\",\ncheck:%s,\n---\nLocal rule body.\n",
		id,
		id,
		spec,
	)
}
rule :: proc(p: ^Probe, topic_name, id, spec: string) {
	source(p, fmt.tprintf(".odx/topics/%s/%s.odx.md", topic_name, id), rule_text(id, spec))
}
fresh :: proc(p: ^Probe, name: string) {
	p.root = fmt.aprintf("%s/%s", p.base, name)
	source(p, "odx.json5", CONFIG)
	source(p, "sample/sample.odin", SOURCE)
}

@(test)
test_contracts :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	odin := os.get_env("ODX_ODIN", context.allocator)
	if odin == "" || !filepath.is_abs(odin) {panic("set ODX_ODIN to an absolute compiler path")}
	base, err := os.make_directory_temp("", "odx-contracts-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(base)
	bin, _ := filepath.abs("build/odx")
	p := Probe {
		t = t,
		bin  = bin,
		base = base,
	}
	fresh(&p, "selectors")
	state, out, errors, compile_err := os.process_exec(
		{command = {odin, "check", fmt.tprintf("%s/sample", p.root), "-no-entry-point"}},
		context.allocator,
	)
	expect(
		&p,
		compile_err == nil && state.exit_code == 0,
		"policy examples compile with reference Odin",
	)
	if compile_err != nil || state.exit_code != 0 {fmt.printfln("%s\n%s", out, errors)}
	invalid_specs := []string {
		`{kind:"pattern",match:"proc",name:"alpha"}`,
		`{kind:"pattern",match:"call",names:["fmt.println"],mutable:false}`,
		`{kind:"pattern",match:"call",names:["fmt.println"],exported:false}`,
		`{kind:"pattern",match:"foreign",name:""}`,
		`{kind:"pattern",match:"decl",at:"package_scope",names:[]}`,
		`{kind:"path_role",mutable:false}`,
		`{kind:"vet_tag",name:null}`,
		`{kind:"pattern",match:"proc",exported:null}`,
		`{kind:"pattern",match:"proc",roles:null}`,
		`{kind:"pattern",match:"proc",requires_param:null}`,
		`{kind:"pattern",match:"proc",requires_param:{index:-1,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:999999999999999999999999,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:+0xFFFFFFFFFFFFFFFFFFFFFFFF,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:0x8000000000000000,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{type_suffix:"Ctx",typo:true}}`,
		`{kind:"pattern",match:"proc",requires_param:{type_suffix:""}}`,
		`{kind:"pattern",match:"call",names:[""]}`,
		`{kind:"pattern",match:"call",names:[]}`,
		`{kind:"pattern",match:"import",name:""}`,
		`{kind:"banned_import",from:"typo"}`,
		`{kind:"require_attribute",attribute:""}`,
		`{kind:"require_attribute",attribute:"require_results",on:"all"}`,
		`{kind:"pattern",match:"proc",kind:"pattern"}`,
	}
	for spec in invalid_specs {run(&p, spec, 2, {"rule", "try", spec, "--count"})}
	trial(&p, "call name sugar", `{kind:"pattern",match:"call",name:"fmt.println"}`, 1)
	trial(
		&p,
		"call union names",
		`{kind:"pattern",match:"call",name:"fmt.println",names:["fmt.printf"]}`,
		1,
	)
	trial(&p, "import glob", `{kind:"pattern",match:"import",name:"core:*"}`, 1)
	trial(&p, "procedures default", `{kind:"pattern",match:"proc"}`, 6)
	trial(&p, "procedures explicit false", `{kind:"pattern",match:"proc",exported:false}`, 6)
	trial(&p, "procedures exported", `{kind:"pattern",match:"proc",exported:true}`, 5)
	trial(
		&p,
		"largest valid index",
		`{kind:"pattern",match:"proc",requires_param:{index:9223372036854775807,type_suffix:"Ctx"}}`,
		6,
	)
	trial(
		&p,
		"first parameter default",
		`{kind:"pattern",match:"proc",requires_param:{type_suffix:"Ctx"}}`,
		4,
	)
	trial(
		&p,
		"grouped second parameter",
		`{kind:"pattern",match:"proc",requires_param:{index:1,type_suffix:"Ctx"}}`,
		5,
	)
	trial(
		&p,
		"mutable declaration",
		`{kind:"pattern",match:"decl",at:"package_scope",mutable:true}`,
		1,
	)
	trial(&p, "all declarations default", `{kind:"pattern",match:"decl",at:"package_scope"}`, 9)
	trial(
		&p,
		"all declarations explicit false",
		`{kind:"pattern",match:"decl",at:"package_scope",mutable:false}`,
		9,
	)
	trial(&p, "foreign categories", `{kind:"pattern",match:"foreign"}`, 2)
	trial(&p, "path role", `{kind:"path_role"}`, 0)
	trial(&p, "vet disabled", `{kind:"vet_tag"}`, 0)
	trial(
		&p,
		"dependency layer absent",
		`{kind:"banned_import",from:"dependencies.may_import"}`,
		0,
	)
	trial(
		&p,
		"compiler attribute selector",
		`{kind:"require_attribute",attribute:"require_results",on:"exported_procs"}`,
		0,
	)
	trial(&p, "custom role", `{kind:"pattern",match:"proc",roles:["domain"]}`, 6)
	trial(
		&p,
		"exclusion wins",
		`{kind:"pattern",match:"proc",roles:["domain"],except_roles:["domain"]}`,
		0,
	)
	source(&p, "odx.json5", `{version:1,odin:{explicit_allocators:"off"}}`)
	trial(&p, "unrestricted no-role", `{kind:"pattern",match:"proc"}`, 6)
	trial(&p, "explicit no-role inclusion", `{kind:"pattern",match:"proc",roles:[""]}`, 6)
	trial(&p, "explicit no-role exclusion", `{kind:"pattern",match:"proc",except_roles:[""]}`, 0)
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:[]},default_role:"domain",odin:{explicit_allocators:"off"}}`,
	)
	trial(&p, "default custom role", `{kind:"pattern",match:"proc",roles:["domain"]}`, 6)

	fresh(&p, "authoring")
	source(&p, "other/other.odin", "package other\nstate: int\n")
	topic(&p, "local")
	spec := `{kind:"pattern",match:"decl",at:"package_scope",mutable:true,roles:["domain"]}`
	rule(&p, "local", "R1", spec)
	trial(&p, "inline parity", spec, 1)
	file := fmt.tprintf("%s/.odx/topics/local/R1.odx.md", p.root)
	text := run(&p, "file parity", 0, {"rule", "try", "--file", file, "--count"})
	expect(&p, strings.trim_space(text) == "1 match", "file trial matches mutable rule")
	inline_locations := run(&p, "inline locations", 0, {"rule", "try", spec})
	file_locations := run(&p, "file locations", 0, {"rule", "try", "--file", file})
	expect(
		&p,
		inline_locations == file_locations &&
		strings.contains(inline_locations, "sample/sample.odin:5:1:"),
		"inline and file trials agree on the violating location",
	)
	r := check(&p, "installed parity", 1)
	expect(
		&p,
		count_rule(r, "local/R1") == 1 && r.violations[0].subject == "state",
		"permanent mutable rule reports state only",
	)
	text = run(
		&p,
		"custom role exclusion guidance",
		0,
		{"for", fmt.tprintf("%s/other", p.root), "--json"},
	)
	expect(
		&p,
		!strings.contains(text, "Project policy marker R1"),
		"stricter policy excludes the unassigned package",
	)
	guidance_commands := [][]string {
		{"for", fmt.tprintf("%s/sample", p.root)},
		{"for", fmt.tprintf("%s/sample", p.root), "--json"},
		{"for", fmt.tprintf("%s/sample", p.root), "--emit-claude-md"},
		{"for", "--emit-claude-md"},
	}
	for args in guidance_commands {
		text = run(&p, "guidance despite topic roles", 0, args)
		expect(
			&p,
			strings.contains(text, "Project policy marker R1"),
			"effective rule appears in guidance",
		)
	}
	source(
		&p,
		"draft.md",
		"---\nid:\"R9\",\nseverity:\"erorr\",\ncheck:{kind:\"pattern\",match:\"proc\"},\n---\nDraft.\n",
	)
	run(
		&p,
		"invalid file metadata",
		2,
		{"rule", "try", "--file", fmt.tprintf("%s/draft.md", p.root)},
	)
	source(
		&p,
		".odx/topics/local/R2.odx.md",
		"---\nid:\"R2\",\nretired:true,\n---\nHistorical rule.\n",
	)
	run(
		&p,
		"retired file trial",
		2,
		{"rule", "try", "--file", fmt.tprintf("%s/.odx/topics/local/R2.odx.md", p.root)},
	)
	run(&p, "retired test", 2, {"rule", "test", "local/R2"})
	run(&p, "unknown test", 2, {"rule", "test", "local/R999"})
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},disabled:{"local/R1":"Adoption deferred deliberately"},odin:{explicit_allocators:"off"}}`,
	)
	r = check(&p, "disabled rule", 0)
	expect(
		&p,
		count_rule(r, "local/R1") == 0 && status(r, "local/R1") == "absent",
		"disabled rule excluded from execution",
	)
	trial(&p, "explicit trial ignores adoption disabling", spec, 1)
	text = run(
		&p,
		"disabled guidance",
		0,
		{"for", fmt.tprintf("%s/sample", p.root), "--emit-claude-md"},
	)
	expect(
		&p,
		!strings.contains(text, "Project policy marker R1"),
		"disabled policy absent from guidance",
	)
	rule(&p, "local", "R1", `{kind:"pattern",match:"proc",name:"alpha"}`)
	run(&p, "disabled malformed definition still rejected", 2, {"check", "--fast"})

	fresh(&p, "overrides")
	topic(&p, "errors")
	rule(&p, "errors", "R90", `{kind:"pattern",match:"foreign",roles:["domain"]}`)
	r = check(&p, "whole topic replacement", 1)
	expect(
		&p,
		count_rule(r, "errors/R90") == 2 && status(r, "errors/R3") == "absent",
		"replacement removes built-in error rule",
	)
	expect(&p, status(r, "dependencies/R3") != "absent", "replacement preserves unrelated topics")
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},disabled:{"errors/R3":"Former built-in policy disabled"},odin:{explicit_allocators:"off"}}`,
	)
	run(&p, "disabled removed rule rejected", 2, {"check", "--fast"})
	source(&p, "odx.json5", CONFIG)
	source(
		&p,
		".odx/topics/errors/R91.odx.md",
		rule_text("R90", `{kind:"pattern",match:"foreign"}`),
	)
	run(&p, "duplicate ID and filename mismatch", 2, {"check", "--fast"})
	source(
		&p,
		".odx/topics/errors/R91.odx.md",
		rule_text("R92", `{kind:"pattern",match:"foreign"}`),
	)
	run(&p, "unique ID filename mismatch", 2, {"check", "--fast"})

	fresh(&p, "configuration")
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"],other:["sample"]},odin:{explicit_allocators:"off"}}`,
	)
	run(&p, "overlapping package roles rejected", 2, {"check", "--fast"})
	source(&p, "odx.json5", `{version:1,default_role:"unknown",odin:{explicit_allocators:"off"}}`)
	run(&p, "undeclared default role rejected", 2, {"check", "--fast"})
	topic(&p, "local")
	rule(&p, "local", "R1", `{kind:"vet_tag",roles:["domain"]}`)
	rule(&p, "local", "R2", `{kind:"banned_import",roles:["domain"]}`)
	source(&p, "odx.json5", CONFIG)
	r = check(&p, "configuration gates off", 0)
	expect(
		&p,
		status(r, "local/R1") == "not_applicable" && status(r, "local/R2") == "not_applicable",
		"disabled vet and absent dependency layer agree with coverage",
	)
	text = run(
		&p,
		"configuration gates guidance",
		0,
		{"for", fmt.tprintf("%s/sample", p.root), "--json"},
	)
	expect(
		&p,
		!strings.contains(text, "Project policy marker"),
		"configuration-inapplicable rules absent from guidance",
	)
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},dependencies:{domain:{may_import:["core:*"]}},odin:{explicit_allocators:"all"}}`,
	)
	r = check(&p, "configuration gates active", 1)
	expect(
		&p,
		count_rule(r, "local/R1") == 1 && status(r, "local/R2") == "complete",
		"custom-role vet all and dependency layer execute",
	)
	text = run(
		&p,
		"configuration active guidance",
		0,
		{"for", fmt.tprintf("%s/sample", p.root), "--json"},
	)
	expect(
		&p,
		strings.contains(text, "Project policy marker R1") &&
		strings.contains(text, "Project policy marker R2"),
		"active configuration rules appear in guidance",
	)
	fmt.printfln("%d assertions passed; %d failed", p.passed, p.failed)
	testing.expect_value(t, p.failed, 0)
}
