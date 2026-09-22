package odx

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_analysis_returns_project_and_selection_errors :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-analysis-*", context.allocator)
	testing.expect(t, err == nil)
	root = canonical(root)
	defer os.remove_all(root)
	testing.expect(t, os.write_entire_file(join({root, CONFIG_FILE}), "{broken") == nil)
	r, code := analyze({root = root, fast = true})
	testing.expect_value(t, code, EXIT_TOOL)
	testing.expect(t, len(r.tool_errors) > 0)
	testing.expect(t, os.write_entire_file(join({root, CONFIG_FILE}), `{version:1}`) == nil)
	testing.expect(t, os.write_entire_file(join({root, "main.odin"}), "package example\n") == nil)
	for options in ([]Analysis_Options{{root = root, paths = {"nonexistent-package"}, fast = true}, {root = root, paths = {"/"}, fast = true}, {root = root, topics = {"nonexistent-topic"}, fast = true}, {root = root, since = "nonexistent-reference", fast = true}}) {
		r, code = analyze(options)
		testing.expect_value(t, code, EXIT_TOOL)
		testing.expect(t, len(r.tool_errors) > 0)
		testing.expect_value(t, len(r.violations), 0)
	}
}

@(test)
test_analysis_loads_dependency_graph_only_for_applicable_rules :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-analysis-graph-*", context.allocator)
	testing.expect(t, err == nil)
	root = canonical(root)
	defer os.remove_all(root)
	for dir in ([]string{"selected", "dependency", "broken"}) {
		testing.expect(t, os.make_directory(join({root, dir})) == nil)
	}
	for file in ([]struct {
			name, source: string,
		}{{"selected/main.odin", "package selected\nimport \"../dependency\"\n"}, {"dependency/main.odin", "package dependency\nimport \"core:os\"\n"}, {"broken/main.odin", "package broken\nbroken :: proc( {"}}) {
		testing.expect(t, os.write_entire_file(join({root, file.name}), file.source) == nil)
	}
	p := Project {
		root = root,
		dirs = {"broken", "dependency", "selected"},
	}
	p.cfg.default_role = "domain"
	p.cfg.odin.explicit_allocators = .off
	p.cfg.dependencies = make(map[string]Layer)
	p.cfg.dependencies["domain"] = {
		deny       = {"core:os"},
		may_import = {"domain", "core:*"},
	}
	append(
		&p.rb.topics,
		Topic {
			name = "custom",
			rules = {
				{id = "R1", check = {kind = .pattern, match = "call", names = {"panic"}}},
				{id = "R2", check = {kind = .banned_import, roles = {"other"}}},
			},
		},
	)
	paths := []string{join({root, "selected"})}
	c := make_ctx(&p, paths)
	testing.expect_value(t, len(c.graph.packages), 0)
	testing.expect_value(t, len(c.pkgs), 1)
	run_family_b(&c)
	testing.expect_value(t, c.pkgs[0].parse_result.status, Evidence_Status.complete)
	testing.expect_value(t, len(c.r.tool_errors), 0)
	testing.expect_value(t, len(c.r.violations), 0)
	p.rb.topics[0].rules[1].check.roles = nil
	c = make_ctx(&p, paths)
	testing.expect_value(t, len(c.graph.packages), 3)
	testing.expect_value(t, len(c.pkgs), 1)
	testing.expect_value(t, c.graph.packages[0].parse_result.status, Evidence_Status.failed)
	run_family_b(&c)
	init_coverage(&c, Analysis_Options{paths = paths, fast = true})
	collect_coverage(&c, Analysis_Options{paths = paths, fast = true})
	testing.expect_value(t, len(c.r.coverage.graph_packages), 3)
	testing.expect_value(t, len(c.r.violations), 1)
	if len(c.r.violations) == 1 {
		testing.expect_value(t, c.r.violations[0].rule, "custom/R2")
		testing.expect(t, strings.contains(c.r.violations[0].message, "core:os"))
	}
	testing.expect_value(t, c.pkgs[0].import_result.status, Evidence_Status.complete)
}
