package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../../probe"

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

trial :: proc(p: ^probe.Probe, name, spec: string, count: int) {
	topic(p, "trial")
	rule(p, "trial", "R1", spec)
	out := probe.run(p, name, 1 if count > 0 else 0, {"check", "--fast", "--json", "--topic", "trial"})
	r: probe.Report
	probe.expect(p, json.unmarshal_string(out, &r) == nil, fmt.tprintf("%s: valid report", name))
	probe.expect(p, count_rule(r, "trial/R1") == count, fmt.tprintf("%s: %d matches", name, count))
}
check :: proc(p: ^probe.Probe, name: string, code: int) -> probe.Report {
	out := probe.run(p, name, code, {"check", "--fast", "--json"})
	r: probe.Report
	probe.expect(p, json.unmarshal_string(out, &r) == nil, fmt.tprintf("%s: valid report", name))
	return r
}
count_rule :: proc(r: probe.Report, id: string) -> int {
	n := 0
	for v in r.violations {if v.rule == id {n += 1}}
	return n
}
status :: proc(r: probe.Report, id: string) -> string {
	for c in r.coverage.checks {if c.rule == id {return c.status}}
	return "absent"
}
topic :: proc(p: ^probe.Probe, name: string) {
	probe.source(
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
rule :: proc(p: ^probe.Probe, topic_name, id, spec: string) {
	probe.source(p, fmt.tprintf(".odx/topics/%s/%s.odx.md", topic_name, id), rule_text(id, spec))
}
fresh :: proc(p: ^probe.Probe, name: string) {
	p.root = fmt.aprintf("%s/%s", p.base, name)
	probe.source(p, "odx.json5", CONFIG)
	probe.source(p, "sample/sample.odin", SOURCE)
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
	p := probe.Probe {
		t    = t,
		bin  = bin,
		base = base,
	}
	fresh(&p, "selectors")
	state, out, errors, compile_err := os.process_exec(
		{command = {odin, "check", fmt.tprintf("%s/sample", p.root), "-no-entry-point"}},
		context.allocator,
	)
	probe.expect(
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
	topic(&p, "trial")
	for spec in invalid_specs {
		rule(&p, "trial", "R1", spec)
		probe.run(&p, spec, 2, {"check", "--json", "--topic", "trial"})
	}
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
	probe.source(&p, "odx.json5", `{version:1,odin:{explicit_allocators:"off"}}`)
	trial(&p, "unrestricted no-role", `{kind:"pattern",match:"proc"}`, 6)
	trial(&p, "explicit no-role inclusion", `{kind:"pattern",match:"proc",roles:[""]}`, 6)
	trial(&p, "explicit no-role exclusion", `{kind:"pattern",match:"proc",except_roles:[""]}`, 0)
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:[]},default_role:"domain",odin:{explicit_allocators:"off"}}`,
	)
	trial(&p, "default custom role", `{kind:"pattern",match:"proc",roles:["domain"]}`, 6)

	fresh(&p, "authoring")
	probe.source(&p, "other/other.odin", "package other\nstate: int\n")
	topic(&p, "local")
	spec := `{kind:"pattern",match:"decl",at:"package_scope",mutable:true,roles:["domain"]}`
	rule(&p, "local", "R1", spec)
	r := check(&p, "installed mutable rule", 1)
	probe.expect(
		&p,
		count_rule(r, "local/R1") == 1 && r.violations[0].subject == "state",
		"permanent mutable rule reports state only",
	)
	text := probe.run(
		&p,
		"custom role exclusion guidance",
		0,
		{"policy", fmt.tprintf("%s/other", p.root), "--json"},
	)
	probe.expect(
		&p,
		!strings.contains(text, "Project policy marker R1"),
		"stricter policy excludes the unassigned package",
	)
	guidance_commands := [][]string {
		{"policy", fmt.tprintf("%s/sample", p.root)},
		{"policy", fmt.tprintf("%s/sample", p.root), "--json"},
		{"policy"},
	}
	for args in guidance_commands {
		text = probe.run(&p, "guidance despite topic roles", 0, args)
		probe.expect(
			&p,
			strings.contains(text, "Project policy marker R1"),
			"effective rule appears in guidance",
		)
	}
	probe.source(
		&p,
		".odx/topics/local/R9.odx.md",
		"---\nid:\"R9\",\nseverity:\"erorr\",\ncheck:{kind:\"pattern\",match:\"proc\"},\n---\nDraft.\n",
	)
	probe.run(&p, "invalid installed metadata", 2, {"check", "--fast", "--json"})
	os.remove(fmt.tprintf("%s/.odx/topics/local/R9.odx.md", p.root))
	probe.source(
		&p,
		".odx/topics/local/R2.odx.md",
		"---\nid:\"R2\",\nretired:true,\n---\nHistorical rule.\n",
	)
	r = check(&p, "retired rule excluded", 1)
	probe.expect(
		&p,
		count_rule(r, "local/R2") == 0 && status(r, "local/R2") == "absent",
		"retired rule does not execute",
	)
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},disabled:{"local/R1":"Adoption deferred deliberately"},odin:{explicit_allocators:"off"}}`,
	)
	r = check(&p, "disabled rule", 0)
	probe.expect(
		&p,
		count_rule(r, "local/R1") == 0 && status(r, "local/R1") == "absent",
		"disabled rule excluded from execution",
	)
	text = probe.run(&p, "disabled guidance", 0, {"policy", fmt.tprintf("%s/sample", p.root)})
	probe.expect(
		&p,
		!strings.contains(text, "Project policy marker R1"),
		"disabled policy absent from guidance",
	)
	rule(&p, "local", "R1", `{kind:"pattern",match:"proc",name:"alpha"}`)
	probe.run(&p, "disabled malformed definition still rejected", 2, {"check", "--fast"})

	fresh(&p, "overrides")
	topic(&p, "errors")
	rule(&p, "errors", "R90", `{kind:"pattern",match:"foreign",roles:["domain"]}`)
	r = check(&p, "whole topic replacement", 1)
	probe.expect(
		&p,
		count_rule(r, "errors/R90") == 2 && status(r, "errors/R3") == "absent",
		"replacement removes built-in error rule",
	)
	probe.expect(&p, status(r, "dependencies/R3") != "absent", "replacement preserves unrelated topics")
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},disabled:{"errors/R3":"Former built-in policy disabled"},odin:{explicit_allocators:"off"}}`,
	)
	probe.run(&p, "disabled removed rule rejected", 2, {"check", "--fast"})
	probe.source(&p, "odx.json5", CONFIG)
	probe.source(
		&p,
		".odx/topics/errors/R91.odx.md",
		rule_text("R90", `{kind:"pattern",match:"foreign"}`),
	)
	probe.run(&p, "duplicate ID and filename mismatch", 2, {"check", "--fast"})
	probe.source(
		&p,
		".odx/topics/errors/R91.odx.md",
		rule_text("R92", `{kind:"pattern",match:"foreign"}`),
	)
	probe.run(&p, "unique ID filename mismatch", 2, {"check", "--fast"})

	fresh(&p, "configuration")
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"],other:["sample"]},odin:{explicit_allocators:"off"}}`,
	)
	probe.run(&p, "overlapping package roles rejected", 2, {"check", "--fast"})
	probe.source(&p, "odx.json5", `{version:1,default_role:"unknown",odin:{explicit_allocators:"off"}}`)
	probe.run(&p, "undeclared default role rejected", 2, {"check", "--fast"})
	topic(&p, "local")
	rule(&p, "local", "R1", `{kind:"vet_tag",roles:["domain"]}`)
	rule(&p, "local", "R2", `{kind:"banned_import",roles:["domain"]}`)
	probe.source(&p, "odx.json5", CONFIG)
	r = check(&p, "configuration gates off", 0)
	probe.expect(
		&p,
		status(r, "local/R1") == "not_applicable" && status(r, "local/R2") == "not_applicable",
		"disabled vet and absent dependency layer agree with coverage",
	)
	text = probe.run(
		&p,
		"configuration gates guidance",
		0,
		{"policy", fmt.tprintf("%s/sample", p.root), "--json"},
	)
	probe.expect(
		&p,
		!strings.contains(text, "Project policy marker"),
		"configuration-inapplicable rules absent from guidance",
	)
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},dependencies:{domain:{may_import:["core:*"]}},odin:{explicit_allocators:"all"}}`,
	)
	r = check(&p, "configuration gates active", 1)
	probe.expect(
		&p,
		count_rule(r, "local/R1") == 1 && status(r, "local/R2") == "complete",
		"custom-role vet all and dependency layer execute",
	)
	text = probe.run(
		&p,
		"configuration active guidance",
		0,
		{"policy", fmt.tprintf("%s/sample", p.root), "--json"},
	)
	probe.expect(
		&p,
		strings.contains(text, "Project policy marker R1") &&
		strings.contains(text, "Project policy marker R2"),
		"active configuration rules appear in guidance",
	)
	fmt.printfln("%d assertions passed; %d failed", p.passed, p.failed)
	testing.expect_value(t, p.failed, 0)
}
