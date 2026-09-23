package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../../probe"

report :: proc(p: ^probe.Probe, name: string, code: int, args: []string, compiler := "") -> probe.Report {
	out := probe.run(p, name, code, args, compiler)
	r: probe.Report
	probe.expect(
		p,
		json.unmarshal_string(out, &r) == nil && r.schema == 2,
		fmt.tprintf("%s schema 2 JSON report", name),
	)
	return r
}
has :: proc(r: probe.Report, rule: string) -> bool {
	for v in r.violations {if v.rule == rule {return true}}
	return false
}

@(test)
test_adoption :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-adoption-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(root)
	bin := os.get_env("ODX_PROBE_BIN", context.allocator)
	if bin == "" {bin, _ = filepath.abs("build/odx")}
	p := probe.Probe {
		t = t,
		bin  = bin,
		root = root,
	}
	config :: `{version:1,disabled:{"errors/R3":"No error convention"},odin:{explicit_allocators:"off",audit_file_tags:false}}`
	probe.source(&p, "odx.json5", config)
	probe.source(
		&p,
		".odx/topics/adoption/topic.md",
		"---\nname:\"adoption\",summary:\"Gradual adoption probe\",\n---\nLocal source policy.\n",
	)
	probe.source(
		&p,
		".odx/topics/adoption/R1.odx.md",
		`---
id:"R1",statement:"No package variables",why:"Caller-owned state",instead_of:"Shared state",evidence:"Native syntax",cost:"Explicit state passing",severity:"warning",check:{kind:"pattern",match:"decl",at:"package_scope",mutable:true},
---
No package-scope mutable declarations.
`,
	)
	probe.source(&p, "lib/old.odin", "package lib\nold: int\n")
	r := report(&p, "warning advisory", 0, {"check", "--json"})
	probe.expect(
		&p,
		r.coverage.complete && r.summary.warnings == 1 && r.summary.errors == 0,
		"advisory warning has complete source evidence",
	)
	r = report(&p, "warning strict", 1, {"check", "--json", "--strict"})
	probe.expect(
		&p,
		len(r.violations) == 1 &&
		r.violations[0].severity == "warning",
		"strict preserves warning severity",
	)
	probe.run(&p, "freeze old warning", 0, {"baseline", "regen"})
	r = report(&p, "baselined warning strict", 0, {"check", "--json", "--strict"})
	probe.expect(
		&p,
		r.summary.baselined == 1 &&
		r.summary.warnings == 0 &&
		len(r.violations) == 1 &&
		r.violations[0].baselined,
		"accepted warning remains visible without failing strict",
	)
	probe.source(&p, "lib/new.odin", "package lib\nnew: int\nnewer: int\n")
	r = report(&p, "new warnings advisory", 0, {"check", "--json"})
	probe.expect(
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
	probe.expect(
		&p,
		r.summary.warnings == 2 &&
		r.summary.baselined == 1 &&
		r.summary.omitted == 2 &&
		len(r.violations) == 1,
		"truncation preserves all exit counts",
	)
	baseline := probe.read(&p, "odx.baseline")
	r = report(
		&p,
		"unrelated warnings do not fail ignore audit",
		0,
		{"ignores", "--stale", "--json"},
	)
	probe.expect(
		&p,
		r.coverage.complete && r.summary.warnings == 3 && r.summary.baselined == 0,
		"ignore audit exposes unsoftened unrelated findings",
	)
	probe.source(
		&p,
		"lib/new.odin",
		"package lib\n// odx:ignore adoption/R1 reason: Required for compatibility\nnew: int\n",
	)
	r = report(&p, "reasoned suppression", 0, {"check", "--json", "--strict"})
	probe.expect(
		&p,
		r.summary.ignored == 1 && r.summary.baselined == 1,
		"suppression removes new warning while old warning remains baselined",
	)
	probe.source(
		&p,
		"lib/old.odin",
		"package lib\n// odx:ignore adoption/R1 reason: Required for compatibility\nold: int\n",
	)
	r = report(&p, "ignore audit skips stale baseline", 0, {"ignores", "--stale", "--json"})
	probe.expect(
		&p,
		r.coverage.complete && r.summary.ignored == 2 && len(r.tool_errors) == 0,
		"baseline state does not invalidate suppression audit",
	)
	probe.expect(&p, probe.read(&p, "odx.baseline") == baseline, "JSON ignore audit preserves baseline bytes")
	probe.run(&p, "text ignore audit", 0, {"ignores", "--stale"})
	probe.expect(&p, probe.read(&p, "odx.baseline") == baseline, "text ignore audit preserves baseline bytes")
	probe.source(
		&p,
		"lib/new.odin",
		"package lib\n// odx:ignore adoption/R1 Required for compatibility\nnew: int\n",
	)
	r = report(&p, "missing reason marker", 1, {"ignores", "--stale", "--json"})
	probe.expect(
		&p,
		has(r, "odx/bad-ignore") && has(r, "adoption/R1") && r.coverage.complete,
		"malformed directive cannot suppress warning",
	)
	probe.source(
		&p,
		"lib/new.odin",
		"package lib\n// odx:ignore adoption/R1 reason: Required for compatibility\nnew :: 1\n",
	)
	r = report(&p, "stale suppression", 1, {"ignores", "--stale", "--json"})
	probe.expect(
		&p,
		has(r, "odx/stale-ignore") && r.coverage.complete,
		"resolved declaration makes suppression stale",
	)
	text := probe.run(&p, "text stale suppression", 1, {"ignores", "--stale"})
	probe.expect(
		&p,
		strings.contains(text, "odx/stale-ignore"),
		"text audit identifies stale suppression",
	)
	probe.source(
		&p,
		"lib/new.odin",
		"package lib\n// odx:ignore adoption/R1 reason: Required for compatibility\nnew: proc(\n",
	)
	r = report(&p, "failed source ignore audit", 2, {"ignores", "--stale", "--json"})
	probe.expect(
		&p,
		!r.coverage.complete && has(r, "odin/syntax") && !has(r, "odx/stale-ignore"),
		"parse failure is visible and cannot certify stale suppression",
	)
	text = probe.run(&p, "text failed source audit", 2, {"ignores", "--stale"})
	probe.expect(&p, strings.contains(text, "odin/syntax"), "text audit exposes syntax failure")
	probe.expect(&p, probe.read(&p, "odx.baseline") == baseline, "failed audits preserve baseline bytes")
	probe.source(&p, "lib/new.odin", "package lib\nnew :: 1\n")
	probe.source(&p, "odx.json5", `{version:1,odin:{explicit_allocators:"off",audit_file_tags:false}}`)
	r = report(
		&p,
		"unavailable compiler ignore audit",
		2,
		{"ignores", "--stale", "--json"},
		fmt.tprintf("%s/missing-odin", p.root),
	)
	probe.expect(
		&p,
		!r.coverage.complete && len(r.tool_errors) > 0,
		"unavailable compiler produces structured audit failure",
	)
	probe.expect(
		&p,
		probe.read(&p, "odx.baseline") == baseline,
		"unavailable compiler audit preserves baseline bytes",
	)
	fmt.printfln("adoption: %d passed, %d failed", p.passed, p.failed)
	testing.expect_value(t, p.failed, 0)
}
