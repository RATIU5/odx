package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../../probe"

CONFIG :: `{version:1,roles:{domain:["sample"]},odin:{explicit_allocators:"off"}}`
PREFIX :: "# Human instructions\n\nPreserve these bytes.\n"
SUFFIX :: "\n## Human footer\n\nKeep this too.\n"
BEGIN :: "<!-- odx:begin v1 -->"
END :: "<!-- odx:end -->"

fresh :: proc(p: ^probe.Probe, name: string) {
	p.root = fmt.aprintf("%s/%s", p.base, name)
	probe.source(p, "odx.json5", CONFIG)
	probe.source(p, "sample/sample.odin", "package sample\nvalue :: 42\n")
}
topic :: proc(p: ^probe.Probe, name: string) {
	probe.source(
		p,
		fmt.tprintf(".odx/topics/%s/topic.md", name),
		fmt.tprintf(
			"---\nname:%q,\nsummary:\"Local policy\",\n---\nLocal context.\n\n## Reader checks\n\nReview ownership manually.\n",
			name,
		),
	)
}
rule :: proc(p: ^probe.Probe, name, id, selector: string) {
	probe.source(
		p,
		fmt.tprintf(".odx/topics/%s/%s.odx.md", name, id),
		fmt.tprintf(
			"---\nid:%q,\nstatement:\"Use project wrappers\",\nwhy:\"Keep calls reviewable\",\ninstead_of:\"Unrestricted calls\",\nevidence:\"Integration test\",\ncost:\"Intentional restriction\",\nseverity:\"error\",\ncheck:%s,\n---\nLocal policy.\n",
			id,
			selector,
		),
	)
}
stale :: proc(p: ^probe.Probe, name: string) {
	before := probe.read(p, "AGENTS.md")
	probe.run(p, name, 1, {"policy", "--verify", "AGENTS.md"})
	probe.expect(p, probe.read(p, "AGENTS.md") == before, fmt.tprintf("%s leaves document untouched", name))
	probe.run(p, fmt.tprintf("%s regenerate", name), 0, {"policy", "--write", "AGENTS.md"})
	probe.expect(p, probe.read(p, "AGENTS.md") != before, fmt.tprintf("%s changes owned content", name))
	probe.run(p, fmt.tprintf("%s now current", name), 0, {"policy", "--verify", "AGENTS.md"})
}

@(test)
test_guidance :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	base, err := os.make_directory_temp("", "odx-guidance-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(base)
	bin, _ := filepath.abs("build/odx")
	p := probe.Probe {
		t    = t,
		bin  = bin,
		base = base,
	}
	fresh(&p, "ownership")
	probe.run(&p, "missing document stale", 1, {"policy", "--verify", "AGENTS.md"})
	probe.expect(
		&p,
		!os.exists(fmt.tprintf("%s/AGENTS.md", p.root)),
		"missing check does not create document",
	)
	probe.source(&p, "AGENTS.md", PREFIX)
	probe.run(&p, "missing block stale", 1, {"policy", "--verify", "AGENTS.md"})
	probe.expect(&p, probe.read(&p, "AGENTS.md") == PREFIX, "missing block check preserves human content")
	probe.run(&p, "append owned block", 0, {"policy", "--write", "AGENTS.md"})
	generated := probe.read(&p, "AGENTS.md")
	probe.expect(
		&p,
		strings.has_prefix(generated, PREFIX) &&
		strings.contains(generated, BEGIN) &&
		strings.contains(generated, END),
		"generated block follows human prefix",
	)
	probe.source(&p, "AGENTS.md", strings.concatenate({generated, SUFFIX}))
	probe.run(&p, "human suffix permitted", 0, {"policy", "--verify", "AGENTS.md"})
	before := probe.read(&p, "AGENTS.md")
	probe.run(&p, "idempotent write", 0, {"policy", "--write", "AGENTS.md"})
	probe.expect(&p, probe.read(&p, "AGENTS.md") == before, "second write is byte identical")
	probe.run(&p, "portable target creation", 0, {"policy", "--write", "POLICY.md"})
	probe.run(&p, "portable target freshness", 0, {"policy", "--verify", "POLICY.md"})
	neutral := probe.read(&p, "POLICY.md")
	probe.expect(
		&p,
		strings.contains(before, neutral),
		"managed rendering is identical across destinations",
	)

	probe.source(
		&p,
		"odx.json5",
		`{ // same effective policy, different field order
odin:{explicit_allocators:"off"}, roles:{domain:["sample"]}, version:1,
}`,
	)
	probe.run(&p, "config comments and key order stable", 0, {"policy", "--verify", "AGENTS.md"})
	probe.source(&p, "sample/sample.odin", "package sample\nvalue :: 43\n")
	probe.run(
		&p,
		"source body edits preserve instruction freshness",
		0,
		{"policy", "--verify", "AGENTS.md"},
	)
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},odin:{explicit_allocators:"off"},errors:{types:["Failure"]}}`,
	)
	stale(&p, "error classification change")
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},odin:{explicit_allocators:"off",flags:["-strict-style"]},errors:{types:["Failure"]}}`,
	)
	stale(&p, "compiler flags change")
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},dependencies:{domain:{may_import:["core:*"],deny:["core:os"]}},odin:{explicit_allocators:"off"}}`,
	)
	stale(&p, "dependency policy change")
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"]},dependencies:{domain:{may_import:["core:*"],deny:["core:net"]}},odin:{explicit_allocators:"off"}}`,
	)
	stale(&p, "dependency deny change without rule text change")
	probe.source(&p, "other/other.odin", "package other\n")
	stale(&p, "new package discovery")
	probe.source(
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
	probe.source(
		&p,
		"odx.json5",
		`{version:1,roles:{domain:["sample"],boundary:["other"]},disabled:{"local/R1":"Deferred for migration"},odin:{explicit_allocators:"off"}}`,
	)
	stale(&p, "rule disabling")
	probe.expect(
		&p,
		!strings.contains(probe.read(&p, "AGENTS.md"), "**local/R1**"),
		"disabled rule absent from instructions",
	)
	topic(&p, "errors")
	rule(&p, "errors", "R90", `{kind:"pattern",match:"foreign"}`)
	stale(&p, "builtin topic replacement")
	probe.expect(
		&p,
		strings.contains(probe.read(&p, "AGENTS.md"), "errors/R90") &&
		!strings.contains(probe.read(&p, "AGENTS.md"), "**errors/R3**"),
		"whole-topic replacement reflected in instructions",
	)
	probe.expect(
		&p,
		strings.has_prefix(probe.read(&p, "AGENTS.md"), PREFIX) &&
		strings.has_suffix(probe.read(&p, "AGENTS.md"), SUFFIX),
		"all regenerations preserve human boundaries",
	)

	fresh(&p, "scope")
	probe.source(&p, "other/other.odin", "package other\n")
	topic(&p, "local")
	rule(&p, "local", "R1", `{kind:"pattern",match:"call",name:"fmt.println",roles:["domain"]}`)
	policy_json := probe.run(
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
	probe.expect(&p, json.unmarshal_string(policy_json, &policy) == nil, "policy context JSON decodes")
	probe.expect(
		&p,
		policy.schema == 2 && len(policy.packages) == 1 && len(policy.rules) == 1,
		"policy context selects one package and rule",
	)
	if len(policy.rules) ==
	   1 {probe.expect(&p, policy.rules[0].id == "local/R1" && policy.rules[0].fix_hint == "Use project wrappers", "policy context preserves correction")}
	probe.expect(&p, len(policy.advice) == 0, "single rule context excludes unrelated reviewer advice")
	checklist := probe.run(
		&p,
		"scoped reader checklist",
		0,
		{"policy", "sample", "--topic", "local", "--checklist", "--json"},
	)
	policy = {}
	probe.expect(
		&p,
		json.unmarshal_string(checklist, &policy) == nil &&
		len(policy.rules) == 0 &&
		len(policy.advice) == 1,
		"checklist separates advice from enforcement",
	)
	probe.run(
		&p,
		"partial managed export rejected",
		2,
		{"policy", "--topic", "local", "--write", "PARTIAL.md", "--json"},
	)
	probe.expect(
		&p,
		!os.exists(fmt.tprintf("%s/PARTIAL.md", p.root)),
		"rejected partial export never creates file",
	)
	probe.run(
		&p,
		"conflicting managed modes rejected",
		2,
		{"policy", "--write", "A.md", "--verify", "B.md"},
	)
	probe.run(&p, "unknown policy topic rejected", 2, {"policy", "--topic", "missing", "--json"})
	probe.run(&p, "rule requires topic", 2, {"policy", "--rule", "R1", "--json"})
	probe.run(&p, "package-scoped write", 0, {"policy", "--write", "AGENTS.md", "sample"})
	probe.run(
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
	probe.run(&p, "different package scope stale", 1, {"policy", "--verify", "AGENTS.md", "other"})
	probe.run(&p, "whole-project scope stale", 1, {"policy", "--verify", "AGENTS.md"})
	probe.run(&p, "excluded rule package", 0, {"policy", "--write", "CLAUDE.md", "other"})
	probe.expect(
		&p,
		strings.contains(probe.read(&p, "AGENTS.md"), "local/R1") &&
		!strings.contains(probe.read(&p, "CLAUDE.md"), "**local/R1**"),
		"package guidance agrees with role applicability",
	)

	probe.source(
		&p,
		"sample/sample.odin",
		"package sample\nimport \"core:fmt\"\nexercise :: proc() {fmt.println(\"hello\")}\n",
	)
	result := probe.run(&p, "corrective JSON finding", 1, {"check", "--fast", "--json"})
	report: probe.Report
	probe.expect(&p, json.unmarshal_string(result, &report) == nil, "corrective finding JSON decodes")
	probe.expect(&p, report.schema == 2, "diagnostic schema is version 2")
	found := false
	for v in report.violations {
		if v.rule != "local/R1" {continue}
		found = true
		probe.expect(
			&p,
			report.rules[v.rule].fix_hint == "Use project wrappers" &&
			report.rules[v.rule].instead_of == "Unrestricted calls",
			"repair direction and discouraged alternative are separate",
		)
		probe.expect(
			&p,
			report.rules[v.rule].evidence != "" && report.rules[v.rule].boundary != "",
			"finding carries evidence and coverage boundary",
		)
	}
	probe.expect(&p, found, "custom policy finding emitted")

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
		probe.source(&p, "AGENTS.md", contents)
		probe.run(&p, fmt.tprintf("malformed %d check", i), 2, {"policy", "--verify", "AGENTS.md"})
		probe.run(&p, fmt.tprintf("malformed %d write", i), 2, {"policy", "--write", "AGENTS.md"})
		probe.expect(&p, probe.read(&p, "AGENTS.md") == contents, "malformed ownership is never overwritten")
	}
	probe.source(&p, "AGENTS.md", "# Human text\n\n## odx\nLegacy mixed content.\n")
	before = probe.read(&p, "AGENTS.md")
	probe.run(&p, "legacy heading write refused", 2, {"policy", "--write", "AGENTS.md"})
	probe.expect(&p, probe.read(&p, "AGENTS.md") == before, "legacy ambiguous content preserved")
	probe.run(&p, "directory read error", 2, {"policy", "--verify", "sample"})
	probe.source(&p, "odx.json5", `{version:1,unknown_policy:true}`)
	probe.run(&p, "invalid policy cannot certify freshness", 2, {"policy", "--verify", "AGENTS.md"})
	probe.expect(&p, probe.read(&p, "AGENTS.md") == before, "invalid policy check preserves document")

	fmt.printfln("%d assertions passed; %d failed", p.passed, p.failed)
	testing.expect_value(t, p.failed, 0)
}
