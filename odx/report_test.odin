package odx

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_json_shares_rule_details_and_keeps_truncated_counts :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	r: Report
	rule := Rule {
		id = "R1",
		statement = "Single shared statement",
		fix_hint = "Single shared repair",
		check = {kind = .pattern, match = "decl", at = "package_scope"},
	}
	rb := test_rulebook("local", &rule)
	for i in 1 ..= 3 {
		append(&r.violations, Violation{file = "a.odin", line = i, col = 1, rule = "local/R1"})
	}
	finalize(&r, &rb, false, 2)
	data, err := json.marshal(r)
	testing.expect(t, err == nil)
	text := string(data)
	testing.expect_value(t, strings.count(text, "Single shared repair"), 1)
	testing.expect_value(t, strings.count(text, "Single shared statement"), 1)
	decoded: struct {
		schema:     int,
		rules:      map[string]Rule_Metadata,
		violations: []struct {
			file, rule: string,
			line:       int,
		},
		summary:    struct {
			errors, omitted: int,
		},
	}
	testing.expect(t, json.unmarshal(data, &decoded) == nil)
	testing.expect_value(t, decoded.schema, 2)
	testing.expect_value(t, len(decoded.violations), 2)
	testing.expect_value(t, decoded.violations[1].line, 2)
	testing.expect_value(t, decoded.summary.errors, 3)
	testing.expect_value(t, decoded.summary.omitted, 1)
	testing.expect_value(
		t,
		decoded.rules[decoded.violations[0].rule].fix_hint,
		"Single shared repair",
	)
}

@(test)
test_finalize_counts_and_omitted :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	r: Report
	for i in 1 ..= 4 {
		append(
			&r.violations,
			Violation{file = "a.odin", line = i, rule = "x/R1", baselined = i == 1},
		)
	}
	code := finalize(&r, nil, false, 2)
	testing.expect_value(t, code, EXIT_VIOLATION)
	testing.expect_value(t, r.summary.errors, 3)
	testing.expect_value(t, r.summary.baselined, 1)
	testing.expect_value(t, r.summary.omitted, 2)
	testing.expect_value(t, len(r.violations), 2)
	testing.expect(t, strings.contains(report_text(&r), "2 more violations omitted"))
	only_base: Report
	append(&only_base.violations, Violation{rule = "x/R1", baselined = true})
	testing.expect_value(t, finalize(&only_base, nil, true), 0)
}

@(test)
test_warning_exit_contract :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	for strict in ([]bool{false, true}) {
		for baselined in ([]bool{false, true}) {
			for complete in ([]bool{false, true}) {
				r: Report
				r.coverage.complete = complete
				append(&r.violations, Violation{severity = .warning, baselined = baselined})
				code := finalize(&r, nil, strict)
				testing.expect_value(t, code, EXIT_VIOLATION if strict && !baselined else 0)
				testing.expect_value(t, r.schema, 2)
				testing.expect_value(t, r.summary.warnings, 0 if baselined else 1)
				testing.expect_value(t, r.summary.baselined, 1 if baselined else 0)
				testing.expect_value(t, r.coverage.complete, complete)
			}
		}
	}
	r: Report
	append(&r.violations, Violation{severity = .warning})
	tool_error(&r, "required graph evidence unavailable")
	testing.expect_value(t, finalize(&r, nil, true), EXIT_TOOL)
}

@(test)
test_repair_metadata_and_order :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	r := Rule {
		id = "R1",
		statement = "No mutable globals.",
		why = "State belongs to the caller.",
		instead_of = "Mutable global state.",
		fix_hint = "Pass state as a parameter.",
		check = {kind = .pattern, match = "decl", at = "package_scope", mutable = true},
	}
	a := Active_Rule{"local/R1", &r}
	rb := test_rulebook("local", &r)
	c := Ctx {
		rb = &rb,
		r  = new(Report),
	}
	report(&c, &a, "lib/a.odin", 2, 1, "second", "z")
	report(&c, &a, "lib/a.odin", 2, 1, "second", "a")
	report(&c, &a, "lib/a.odin", 2, 1, "first", "a")
	finalize(c.r, &rb, false)
	v := c.r.violations[0]
	testing.expect_value(t, v.subject, "a")
	testing.expect_value(t, v.message, "first")
	testing.expect_value(t, c.r.violations[2].subject, "z")
	metadata := c.r.rules["local/R1"]
	testing.expect_value(t, metadata.fix_hint, "Pass state as a parameter.")
	testing.expect_value(t, metadata.instead_of, "Mutable global state.")
	evidence, boundary := rule_evidence(r.check)
	testing.expect_value(t, metadata.evidence, evidence)
	testing.expect_value(t, metadata.boundary, boundary)
	testing.expect(t, strings.contains(report_text(c.r), "repair: Pass state as a parameter."))
	testing.expect(t, strings.contains(report_text(c.r), "evidence: native_ast;"))
	testing.expect_value(t, strings.count(report_text(c.r), "repair:"), 1)
	r.fix_hint = ""
	testing.expect_value(t, rule_fix_hint(&r), r.statement)
}

@(test)
test_json_resolves_compiler_and_internal_finding_metadata :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	r: Report
	append(
		&r.coverage.checks,
		Check_Coverage {
			rule = "odin/check",
			evidence = "compiler_diagnostics",
			boundary = "Configured compiler target",
		},
		Check_Coverage {
			rule = "odin/syntax",
			evidence = "native_parser",
			boundary = "Selected source files",
		},
	)
	note(&r, "odin/error", "odin", "main.odin", 1, 1, "Type mismatch")
	note(&r, "odin/syntax", "parse", "bad.odin", 1, 1, "Syntax error")
	note(&r, "odx/bad-ignore", "ignore", "main.odin", 2, 1, "Invalid ignore")
	finalize(&r, nil, false)
	data, encode_error := json.marshal(r)
	testing.expect(t, encode_error == nil)
	decoded: Report
	testing.expect(t, json.unmarshal(data, &decoded) == nil)
	for v in decoded.violations {
		metadata, found := decoded.rules[v.rule]
		testing.expect(t, found, v.rule)
		testing.expect(t, metadata.check != "", v.rule)
	}
	testing.expect_value(t, decoded.rules["odin/error"].evidence, "compiler_diagnostics")
	testing.expect_value(t, decoded.rules["odin/error"].boundary, "Configured compiler target")
	testing.expect_value(t, decoded.rules["odin/syntax"].evidence, "native_parser")
	testing.expect_value(t, decoded.rules["odin/syntax"].boundary, "Selected source files")
	testing.expect_value(t, decoded.rules["odx/bad-ignore"].check, "ignore")
	testing.expect_value(t, decoded.rules["odx/bad-ignore"].evidence, "")
}

@(test)
test_shared_policy_rule_preserves_repairs_and_finding_provenance :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	rule := Rule {
		id = "R1",
		statement = "Required policy",
		why = "Policy reason",
		fix_hint = "Repair this policy",
		instead_of = "Rejected form",
		fires = "Bad example",
		silent = "Good example",
		class = "policy_class",
		check = {kind = .pattern, match = "decl", at = "package_scope"},
	}
	rb := test_rulebook("local", &rule)
	policy := Violation {
		file  = "a.odin",
		line  = 1,
		col   = 1,
		rule  = "local/R1",
		check = "pattern",
	}
	compiler := Violation {
		file    = "a.odin",
		line    = 2,
		col     = 1,
		rule    = "local/R1",
		check   = "odin",
		message = "Compiler diagnostic classified as the same policy",
	}
	evidence, boundary := rule_evidence(rule.check)
	for compiler_first in ([]bool{false, true}) {
		r: Report
		append(
			&r.coverage.checks,
			Check_Coverage {
				rule = "odin/check",
				evidence = "compiler_diagnostics",
				boundary = "Compiler target",
			},
		)
		if compiler_first {append(&r.violations, compiler, policy)} else {append(&r.violations, policy, compiler)}
		finalize(&r, &rb, false)
		data, encode_error := json.marshal(r)
		testing.expect(t, encode_error == nil)
		decoded: Report
		testing.expect(t, json.unmarshal(data, &decoded) == nil)
		metadata := decoded.rules["local/R1"]
		testing.expect_value(t, metadata.statement, rule.statement)
		testing.expect_value(t, metadata.fix_hint, rule.fix_hint)
		testing.expect_value(t, metadata.why, rule.why)
		testing.expect_value(t, metadata.check, "pattern")
		testing.expect_value(t, metadata.class, rule.class)
		testing.expect_value(t, metadata.instead_of, rule.instead_of)
		testing.expect_value(t, metadata.fires, rule.fires)
		testing.expect_value(t, metadata.silent, rule.silent)
		testing.expect_value(t, metadata.evidence, evidence)
		testing.expect_value(t, metadata.boundary, boundary)
		testing.expect_value(t, decoded.violations[0].check, "pattern")
		testing.expect_value(t, decoded.violations[1].check, "odin")
	}
}

// test_rulebook: a one-topic, one-rule rulebook so finalize can resolve "<topic>/<rule.id>".
test_rulebook :: proc(topic: string, rule: ^Rule) -> (rb: Rulebook) {
	rules := make([]Rule, 1)
	rules[0] = rule^
	append(&rb.topics, Topic{name = topic, rules = rules})
	return
}
