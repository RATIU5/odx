package odx

import "core:strings"
import "core:testing"

@(test)
test_policy_projection_keeps_applicable_rules_and_advice_separate :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	p := Project {
		dirs = {"domain", "edge"},
	}
	p.cfg.default_role = "domain"
	p.cfg.disabled = make(map[string]string)
	p.cfg.disabled["custom/R2"] = "Project disables this rule"
	topic := Topic {
		name     = "custom",
		prose    = "Ignored introduction" + READER_CHECKS_HEADING + "Review ownership.",
		exemplar = "Do not export this source",
		rules    = {
			{id = "R1", statement = "Use do", check = {kind = .pattern, match = "if"}},
			{id = "R2", check = {kind = .pattern, match = "if"}},
			{id = "R3", retired = true, check = {kind = .pattern, match = "if"}},
		},
	}
	append(&p.rb.topics, topic)
	topics := applicable_topics(&p, p.dirs)
	policy := policy_context(&p, p.dirs, topics)
	testing.expect_value(t, policy.schema, 2)
	testing.expect(t, !policy.catalog)
	testing.expect_value(t, len(policy.packages), 2)
	testing.expect_value(t, len(policy.rules), 1)
	testing.expect_value(t, policy.rules[0].id, "custom/R1")
	testing.expect_value(t, len(policy.advice), 1)
	testing.expect_value(t, policy.advice[0].advice, "Review ownership.")
	rendered := guidance_json(policy)
	testing.expect(t, !strings.contains(rendered, "Do not export this source"))
	testing.expect(t, !strings.contains(rendered, "Ignored introduction"))
	testing.expect(t, !strings.contains(rendered, "requires_param"))
	checklist := policy_context(&p, p.dirs, topics, checklist = true)
	testing.expect_value(t, len(checklist.rules), 0)
	testing.expect_value(t, len(checklist.advice), 1)
	one := policy_context(&p, p.dirs, topics, rule = "R1")
	testing.expect_value(t, len(one.rules), 1)
	testing.expect_value(t, len(one.advice), 0)
}

@(test)
test_managed_policy_fingerprints_config_without_dumping_it :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	p := Project {
		dirs = {"example"},
	}
	p.cfg.errors.types = {"PrivateErrorSuffix"}
	first := guidance_block(&p, p.dirs, false)
	testing.expect(t, !strings.contains(first, "PrivateErrorSuffix"))
	testing.expect(t, !strings.contains(first, "Configured policy"))
	testing.expect(t, strings.contains(first, "odx policy --verify"))
	p.cfg.errors.types = {"DifferentPrivateErrorSuffix"}
	second := guidance_block(&p, p.dirs, false)
	testing.expect(t, first != second)
	region, err := guidance_region(second)
	testing.expect(t, err == "" && region.found && region.start == 0 && region.end == len(second))
}
