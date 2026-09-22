package validation

import "core:fmt"
import "core:os"
import "core:strings"

maintenance :: proc(p: ^Probe, policy, source: string, original: Report) {
	config_path := fmt.tprintf("%s/odx.json5", p.root)
	config := read(config_path)
	changed, _ := strings.replace_all(config, "exclude:[", "exclude:[\"pilot_generated/**\",")
	write(config_path, changed)
	_, stale_code, _ := run(p, "guidance-policy-drift", {"policy", "--verify", "AGENTS.md"})
	expect(p, stale_code == 1, "effective configuration change stales guidance")
	write(config_path, config)
	_, fresh_code, _ := run(p, "guidance-policy-restored", {"policy", "--verify", "AGENTS.md"})
	expect(p, fresh_code == 0, "restored policy matches original guidance")
	if !original.coverage.complete {return}
	_, regen_code, _ := run(p, "baseline-accept", {"baseline", "regen"})
	expect(p, regen_code == 0, "complete real source permits explicit baseline acceptance")
	baseline_path := fmt.tprintf("%s/odx.baseline", p.root)
	baseline := read(baseline_path)
	accepted, _, _ := check(p, "baseline-visible")
	expect(p, read(baseline_path) == baseline, "ordinary baseline check never writes")
	source_path := fmt.tprintf("%s/domain/input.odin", p.root)
	write(source_path, strings.concatenate({source, "\n// Pilot maintenance comment.\n"}))
	edited, _, _ := check(p, "baseline-comment-edit")
	expect(
		p,
		edited.summary.baselined == 0,
		"source comment edit reopens accepted source snapshots",
	)
	expect(p, read(baseline_path) == baseline, "maintenance check preserves acceptance bytes")
	if accepted.summary.baselined >
	   0 {expect(p, len(edited.tool_errors) > 0, "stale source acceptance requires explicit maintenance")}
	write(source_path, source)
	expect(
		p,
		os.remove(baseline_path) == nil,
		"remove generated acceptance before counterexamples",
	)
	if policy == "strict" && strings.contains(source, "package container_queue") {
		corrected, _ := strings.replace_all(
			source,
			"\ninit :: proc",
			"\n@(require_results)\ninit :: proc",
		)
		write(source_path, corrected)
		repaired, _, _ := check(p, "repair-real-init-result-contract")
		still_fires := false
		for v in repaired.violations {if v.rule == "errors/R3" && v.subject == "init" {still_fires = true}}
		expect(
			p,
			repaired.coverage.complete && !still_fires,
			"real init attribute correction compiles and removes its finding",
		)
		write(source_path, source)
		regressed, _, _ := check(p, "regress-real-init-result-contract")
		expect(
			p,
			encoded(regressed.violations) == encoded(original.violations),
			"removing real correction restores original diagnostics",
		)
	}

	// Changes stay confined to a temporary copy of real upstream code.
	if policy == "minimal" {
		mutation := strings.concatenate({source, "\nPilot_Mutable: int\n"})
		write(source_path, mutation)
		violating, _, _ := check(p, "mutation-mutable")
		found := false
		for v in violating.violations {if v.rule == "library/R1" && v.subject == "Pilot_Mutable" {found = true}}
		expect(p, found, "new mutable declaration in real source detected")
		expect(p, violating.coverage.complete, "mutable mutation is compiler valid")
		legitimate := strings.concatenate(
			{
				source,
				"\n// foreign import is explanatory prose.\nPilot_Description :: \"foreign import fake library; Pilot_Mutable: int\"\n",
			},
		)
		write(source_path, legitimate)
		harmless, _, _ := check(p, "mutation-comment-string")
		expect(
			p,
			encoded(harmless.violations) == encoded(original.violations),
			"comment/string lookalikes create no source findings",
		)
		expect(p, harmless.coverage.complete, "comment/string counterexample is compiler valid")
		write(source_path, source)
	}
}
