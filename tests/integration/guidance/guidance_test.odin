package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Probe :: struct {
	t:               ^testing.T,
	bin, root, base: string,
	passed, failed:  int,
}

Report :: struct {
	schema:     int,
	violations: []struct {
		rule: string,
	},
	rules:      map[string]struct {
		fix_hint, instead_of, evidence, boundary: string,
	},
}

CONFIG :: `{version:1,roles:{domain:["sample"]},odin:{explicit_allocators:"off"}}`
PREFIX :: "# Human instructions\n\nPreserve these bytes.\n"
SUFFIX :: "\n## Human footer\n\nKeep this too.\n"
BEGIN :: "<!-- odx:begin v1 -->"
END :: "<!-- odx:end -->"

write :: proc(path, contents: string) {
	err := os.make_directory_all(filepath.dir(path))
	if err != nil && err != os.General_Error.Exist {panic(fmt.tprintf("%v", err))}
	if err = os.write_entire_file(path, contents); err != nil {panic(fmt.tprintf("%v", err))}
}
source :: proc(p: ^Probe, path, contents: string) {
	write(fmt.tprintf("%s/%s", p.root, path), contents)
}
read :: proc(p: ^Probe, path: string) -> string {
	data, err := os.read_entire_file(fmt.tprintf("%s/%s", p.root, path), context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	return string(data)
}
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
fresh :: proc(p: ^Probe, name: string) {
	p.root = fmt.aprintf("%s/%s", p.base, name)
	source(p, "odx.json5", CONFIG)
	source(p, "sample/sample.odin", "package sample\nvalue :: 42\n")
}
topic :: proc(p: ^Probe, name: string) {
	source(
		p,
		fmt.tprintf(".odx/topics/%s/topic.md", name),
		fmt.tprintf(
			"---\nname:%q,\nsummary:\"Local policy\",\n---\nLocal context.\n\n## Reader checks\n\nReview ownership manually.\n",
			name,
		),
	)
}
rule :: proc(p: ^Probe, name, id, selector: string) {
	source(
		p,
		fmt.tprintf(".odx/topics/%s/%s.odx.md", name, id),
		fmt.tprintf(
			"---\nid:%q,\nstatement:\"Use project wrappers\",\nwhy:\"Keep calls reviewable\",\ninstead_of:\"Unrestricted calls\",\nevidence:\"Integration test\",\ncost:\"Intentional restriction\",\nseverity:\"error\",\ncheck:%s,\n---\nLocal policy.\n",
			id,
			selector,
		),
	)
}
stale :: proc(p: ^Probe, name: string) {
	before := read(p, "AGENTS.md")
	run(p, name, 1, {"policy", "--verify", "AGENTS.md"})
	expect(p, read(p, "AGENTS.md") == before, fmt.tprintf("%s leaves document untouched", name))
	run(p, fmt.tprintf("%s regenerate", name), 0, {"policy", "--write", "AGENTS.md"})
	expect(p, read(p, "AGENTS.md") != before, fmt.tprintf("%s changes owned content", name))
	run(p, fmt.tprintf("%s now current", name), 0, {"policy", "--verify", "AGENTS.md"})
}

@(test)
test_guidance :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	base, err := os.make_directory_temp("", "odx-guidance-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(base)
	bin, _ := filepath.abs("build/odx")
	p := Probe {
		t    = t,
		bin  = bin,
		base = base,
	}
	fresh(&p, "ownership")
	run(&p, "missing document stale", 1, {"policy", "--verify", "AGENTS.md"})
	expect(
		&p,
		!os.exists(fmt.tprintf("%s/AGENTS.md", p.root)),
		"missing check does not create document",
	)
	source(&p, "AGENTS.md", PREFIX)
	run(&p, "missing block stale", 1, {"policy", "--verify", "AGENTS.md"})
	expect(&p, read(&p, "AGENTS.md") == PREFIX, "missing block check preserves human content")
	run(&p, "append owned block", 0, {"policy", "--write", "AGENTS.md"})
	generated := read(&p, "AGENTS.md")
	expect(
		&p,
		strings.has_prefix(generated, PREFIX) &&
		strings.contains(generated, BEGIN) &&
		strings.contains(generated, END),
		"generated block follows human prefix",
	)
	source(&p, "AGENTS.md", strings.concatenate({generated, SUFFIX}))
	run(&p, "human suffix permitted", 0, {"policy", "--verify", "AGENTS.md"})
	before := read(&p, "AGENTS.md")
	run(&p, "idempotent write", 0, {"policy", "--write", "AGENTS.md"})
	expect(&p, read(&p, "AGENTS.md") == before, "second write is byte identical")
	run(&p, "portable target creation", 0, {"policy", "--write", "POLICY.md"})
	run(&p, "portable target freshness", 0, {"policy", "--verify", "POLICY.md"})
	neutral := read(&p, "POLICY.md")
	expect(
		&p,
		strings.contains(before, neutral),
		"managed rendering is identical across destinations",
	)

	source(
		&p,
		"odx.json5",
		`{ // same effective policy, different field order
odin:{explicit_allocators:"off"}, roles:{domain:["sample"]}, version:1,
}`,
	)
	run(&p, "config comments and key order stable", 0, {"policy", "--verify", "AGENTS.md"})
	source(&p, "sample/sample.odin", "package sample\nvalue :: 43\n")
	run(
		&p,
		"source body edits preserve instruction freshness",
		0,
		{"policy", "--verify", "AGENTS.md"},
	)
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},odin:{explicit_allocators:"off"},errors:{types:["Failure"]}}`,
	)
	stale(&p, "error classification change")
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},odin:{explicit_allocators:"off",flags:["-strict-style"]},errors:{types:["Failure"]}}`,
	)
	stale(&p, "compiler flags change")
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},dependencies:{domain:{may_import:["core:*"],deny:["core:os"]}},odin:{explicit_allocators:"off"}}`,
	)
	stale(&p, "dependency policy change")
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},dependencies:{domain:{may_import:["core:*"],deny:["core:net"]}},odin:{explicit_allocators:"off"}}`,
	)
	stale(&p, "dependency deny change without rule text change")
	source(&p, "other/other.odin", "package other\n")
	stale(&p, "new package discovery")
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"],boundary:["other"]},odin:{explicit_allocators:"off"}}`,
	)
	stale(&p, "package role change")
	topic(&p, "local")
	rule(&p, "local", "R1", `{kind:"pattern",match:"call",name:"fmt.println",roles:["domain"]}`)
	stale(&p, "local policy addition")
	rule(&p, "local", "R1", `{kind:"pattern",match:"call",name:"fmt.printf",roles:["domain"]}`)
	stale(&p, "selector change without statement change")
	source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"],boundary:["other"]},disabled:{"local/R1":"Deferred for migration"},odin:{explicit_allocators:"off"}}`,
	)
	stale(&p, "rule disabling")
	expect(
		&p,
		!strings.contains(read(&p, "AGENTS.md"), "**local/R1**"),
		"disabled rule absent from instructions",
	)
	topic(&p, "errors")
	rule(&p, "errors", "R90", `{kind:"pattern",match:"foreign"}`)
	stale(&p, "builtin topic replacement")
	expect(
		&p,
		strings.contains(read(&p, "AGENTS.md"), "errors/R90") &&
		!strings.contains(read(&p, "AGENTS.md"), "**errors/R3**"),
		"whole-topic replacement reflected in instructions",
	)
	expect(
		&p,
		strings.has_prefix(read(&p, "AGENTS.md"), PREFIX) &&
		strings.has_suffix(read(&p, "AGENTS.md"), SUFFIX),
		"all regenerations preserve human boundaries",
	)

	fresh(&p, "scope")
	source(&p, "other/other.odin", "package other\n")
	topic(&p, "local")
	rule(&p, "local", "R1", `{kind:"pattern",match:"call",name:"fmt.println",roles:["domain"]}`)
	policy_json := run(
		&p,
		"scoped policy context",
		0,
		{"policy", "sample", "--topic", "local", "--rule", "R1", "--json"},
	)
	policy: struct {
		schema:   int,
		packages: []struct {
			path, role: string,
		},
		rules:    []struct {
			id, statement, fix_hint: string,
		},
		advice:   []struct {
			topic, advice: string,
		},
	}
	expect(&p, json.unmarshal_string(policy_json, &policy) == nil, "policy context JSON decodes")
	expect(
		&p,
		policy.schema == 2 && len(policy.packages) == 1 && len(policy.rules) == 1,
		"policy context selects one package and rule",
	)
	if len(policy.rules) ==
	   1 {expect(&p, policy.rules[0].id == "local/R1" && policy.rules[0].fix_hint == "Use project wrappers", "policy context preserves correction")}
	expect(&p, len(policy.advice) == 0, "single rule context excludes unrelated reviewer advice")
	checklist := run(
		&p,
		"scoped reader checklist",
		0,
		{"policy", "sample", "--topic", "local", "--checklist", "--json"},
	)
	policy = {}
	expect(
		&p,
		json.unmarshal_string(checklist, &policy) == nil &&
		len(policy.rules) == 0 &&
		len(policy.advice) == 1,
		"checklist separates advice from enforcement",
	)
	run(
		&p,
		"partial managed export rejected",
		2,
		{"policy", "--topic", "local", "--write", "PARTIAL.md", "--json"},
	)
	expect(
		&p,
		!os.exists(fmt.tprintf("%s/PARTIAL.md", p.root)),
		"rejected partial export never creates file",
	)
	run(
		&p,
		"conflicting managed modes rejected",
		2,
		{"policy", "--write", "A.md", "--verify", "B.md"},
	)
	run(&p, "unknown policy topic rejected", 2, {"policy", "--topic", "missing", "--json"})
	run(&p, "rule requires topic", 2, {"policy", "--rule", "R1", "--json"})
	run(&p, "package-scoped write", 0, {"policy", "--write", "AGENTS.md", "sample"})
	run(
		&p,
		"equivalent absolute scope",
		0,
		{
			"policy",
			"--verify",
			fmt.tprintf("%s/AGENTS.md", p.root),
			fmt.tprintf("%s/sample", p.root),
		},
	)
	run(&p, "different package scope stale", 1, {"policy", "--verify", "AGENTS.md", "other"})
	run(&p, "whole-project scope stale", 1, {"policy", "--verify", "AGENTS.md"})
	run(&p, "excluded rule package", 0, {"policy", "--write", "CLAUDE.md", "other"})
	expect(
		&p,
		strings.contains(read(&p, "AGENTS.md"), "local/R1") &&
		!strings.contains(read(&p, "CLAUDE.md"), "**local/R1**"),
		"package guidance agrees with role applicability",
	)

	source(
		&p,
		"sample/sample.odin",
		"package sample\nimport \"core:fmt\"\nexercise :: proc() {fmt.println(\"hello\")}\n",
	)
	result := run(&p, "corrective JSON finding", 1, {"check", "--fast", "--json"})
	report: Report
	expect(&p, json.unmarshal_string(result, &report) == nil, "corrective finding JSON decodes")
	expect(&p, report.schema == 2, "diagnostic schema is version 2")
	found := false
	for v in report.violations {
		if v.rule != "local/R1" {continue}
		found = true
		expect(
			&p,
			report.rules[v.rule].fix_hint == "Use project wrappers" &&
			report.rules[v.rule].instead_of == "Unrestricted calls",
			"repair direction and discouraged alternative are separate",
		)
		expect(
			&p,
			report.rules[v.rule].evidence != "" && report.rules[v.rule].boundary != "",
			"finding carries evidence and coverage boundary",
		)
	}
	expect(&p, found, "custom policy finding emitted")

	fresh(&p, "malformed")
	malformed := []string {
		"<!-- odx:begin v1 -->\npartial\n",
		"<!-- odx:end -->\n",
		"<!-- odx:end -->\n<!-- odx:begin v1 -->\n",
		"<!-- odx:begin v1 -->\na\n<!-- odx:begin v1 -->\nb\n<!-- odx:end -->\n",
		"<!-- odx:begin v1 -->\na\n<!-- odx:end -->\n<!-- odx:end -->\n",
		"<!-- odx:begin v1 -->\na\n<!-- odx:end -->\n<!-- odx:begin v1 -->\nb\n<!-- odx:end -->\n",
	}
	for contents, i in malformed {
		source(&p, "AGENTS.md", contents)
		run(&p, fmt.tprintf("malformed %d check", i), 2, {"policy", "--verify", "AGENTS.md"})
		run(&p, fmt.tprintf("malformed %d write", i), 2, {"policy", "--write", "AGENTS.md"})
		expect(&p, read(&p, "AGENTS.md") == contents, "malformed ownership is never overwritten")
	}
	source(&p, "AGENTS.md", "# Human text\n\n## odx\nLegacy mixed content.\n")
	before = read(&p, "AGENTS.md")
	run(&p, "legacy heading write refused", 2, {"policy", "--write", "AGENTS.md"})
	expect(&p, read(&p, "AGENTS.md") == before, "legacy ambiguous content preserved")
	run(&p, "directory read error", 2, {"policy", "--verify", "sample"})
	source(&p, "odx.json5", `{version:1,unknown_policy:true}`)
	run(&p, "invalid policy cannot certify freshness", 2, {"policy", "--verify", "AGENTS.md"})
	expect(&p, read(&p, "AGENTS.md") == before, "invalid policy check preserves document")

	fmt.printfln("%d assertions passed; %d failed", p.passed, p.failed)
	testing.expect_value(t, p.failed, 0)
}
