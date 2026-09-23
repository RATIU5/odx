package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:strings"

import "../../probe"

procedure_aliases :: proc(p: ^probe.Probe) {
	original_root := p.root
	p.root = fmt.tprintf("%s/aliases", original_root)
	defer p.root = original_root
	configure(p, `{structural:false}`)
	probe.source(p, "sample/main.odin", `package sample
Error :: enum {None, Bad}
first :: proc() -> Error {return .Bad}; second :: proc() -> Error {return .Bad}
first_alias :: first
first_alias_again :: first_alias
second_alias :: second
@(require_results)
acknowledged :: proc() -> Error {return .None}
acknowledged_alias :: acknowledged
`)
	check(p, "procedure aliases report each distinct declaration once", {"first", "second"})
	probe.source(p, ".odx/topics/acknowledgement/topic.md", `---
name:"acknowledgement", summary:"Independent result acknowledgement policy",
---
Project policy over the same declarations as errors/R3.
`)
	probe.source(p, ".odx/topics/acknowledgement/R1.odx.md", `---
id:"R1", severity:"error", statement:"Selected APIs carry require_results.",
why:"Callers acknowledge results.", instead_of:"Bare calls.",
evidence:"Compiler entities and alias counterexamples.", cost:"Explicit acknowledgement.",
check:{kind:"require_attribute",attribute:"require_results",on:"exported_procs"},
---
Independent policy must still report the same declaration.
`)
	output := probe.run(p, "aliases preserve independent rule findings", 1, {"check", "--json"})
	report: probe.Report
	probe.expect(p, json.unmarshal_string(output, &report) == nil, "alias report decodes")
	probe.expect(p, report.coverage.complete, "aliased declarations have complete compiler evidence")
	probe.expect(p, len(report.violations) == 4, "two declarations reported once for each of two rules")
	for rule in ([]string{"errors/R3", "acknowledgement/R1"}) {
		for name in ([]string{"first", "second"}) {
			count := 0
			for v in report.violations {
				if v.rule == rule && strings.has_prefix(v.message, fmt.tprintf("%s returns ", name)) {count += 1}
			}
			probe.expect(p, count == 1, fmt.tprintf("%s reports %s exactly once", rule, name))
		}
	}
}
