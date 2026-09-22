package odx

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_guidance_matches_rule_scope_despite_topic_roles :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-applicability-*", context.allocator)
	testing.expect(t, err == nil)
	testing.expect(
		t,
		os.write_entire_file(join({root, "main.odin"}), "package example\nstate: int") == nil,
	)
	defer os.remove_all(root)
	p := Project {
		root = root,
		dirs = {""},
	}
	p.cfg.roles = make(map[string][]string)
	p.cfg.roles["domain"] = {}
	p.cfg.default_role = "domain"
	p.cfg.odin.explicit_allocators = .off
	topic := Topic {
		name    = "custom",
		summary = "Scope probe",
	}
	topic.applies_to.roles = {"edge"}
	topic.rules = {
		{
			id = "R1",
			check = {
				kind = .pattern,
				match = "decl",
				at = "package_scope",
				mutable = true,
				roles = {"domain"},
			},
		},
		{
			id = "R2",
			check = {
				kind = .pattern,
				match = "decl",
				at = "package_scope",
				mutable = true,
				except_roles = {"domain"},
			},
		},
	}
	append(&p.rb.topics, topic)
	c := make_ctx(&p, nil)
	run_family_b(&c)
	testing.expect_value(t, len(c.r.violations), 1)
	testing.expect_value(t, c.r.violations[0].rule, "custom/R1")
	guided := applicable_topics(&p, p.dirs)
	testing.expect_value(t, len(guided), 1)
	testing.expect_value(t, len(guided[0].rules), 1)
	testing.expect_value(t, guided[0].rules[0].id, "R1")
	testing.expect_value(t, guided[0].rules[0].scope, "roles domain")
	md := claude_md(&p, guided)
	testing.expect(t, strings.contains(md, "**custom/R1**"))
	testing.expect(t, !strings.contains(md, "custom/R2"))
	testing.expect(t, !strings.contains(md, "Applies to roles edge"))
}

@(test)
test_unmapped_guidance_respects_disabled_and_kind_configuration :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	p := Project {
		dirs = {"package"},
	}
	p.cfg.odin.explicit_allocators = .off
	p.cfg.disabled = make(map[string]string)
	p.cfg.disabled["custom/R2"] = "Disabled for this test"
	disabled := describe_rule(&p.cfg, "custom", Rule{id = "R2"})
	testing.expect_value(t, disabled.disabled_reason, "Disabled for this test")
	testing.expect_value(t, disabled.scope, "all roles, including unmapped packages")
	topic := Topic {
		name = "custom",
	}
	topic.rules = {
		{id = "R1", check = {kind = .pattern, match = "decl", at = "package_scope", roles = {""}}},
		{id = "R2", check = {kind = .pattern, match = "decl", at = "package_scope"}},
		{id = "R3", check = {kind = .banned_import}},
		{id = "R4", check = {kind = .vet_tag}},
		{
			id = "R5",
			check = {kind = .pattern, match = "decl", at = "package_scope", except_roles = {""}},
		},
	}
	append(&p.rb.topics, topic)
	guided := applicable_topics(&p, p.dirs)
	testing.expect_value(t, len(guided), 1)
	testing.expect_value(t, len(guided[0].rules), 1)
	testing.expect_value(t, guided[0].rules[0].id, "R1")
	testing.expect(t, strings.contains(claude_md(&p, guided), "(unmapped)"))
	p.cfg.odin.explicit_allocators = .all
	guided = applicable_topics(&p, p.dirs)
	testing.expect_value(t, len(guided[0].rules), 2)
	testing.expect_value(t, guided[0].rules[1].id, "R4")
}

@(test)
test_inapplicable_entity_rule_never_launches_compiler :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	cfg := Config{}
	cfg.odin.path = "/nonexistent/odx-applicability-compiler"
	rule := Rule {
		check = {kind = .require_attribute, attribute = "require_results", roles = {"domain"}},
	}
	c := Ctx {
		cfg   = &cfg,
		r     = new(Report),
		pkgs  = {{role = "edge", parse_result = {.complete, ""}}},
		rules = {{"custom/R1", &rule}},
	}
	run_family_c(&c)
	testing.expect_value(t, len(c.r.tool_errors), 0)
	testing.expect_value(t, c.pkgs[0].doc_result.status, Evidence_Status.not_run)
}
