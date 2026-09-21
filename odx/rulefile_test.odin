package odx

import "core:strings"
import "core:testing"

@(test)
test_parse_rule_file :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	src := "---\nid: R3\nwhy: it's \"quoted\": yes\nblocking: true\ncheck: { kind: require_attribute, attribute: require_results }\n---\n\nProse before.\n\n```odin prelude\nError :: enum { None }\n```\n\n```odin fires\nread :: proc() -> Error { return .None }\n```\n\n```odin\nsample :: 1\n```\n\n```odin silent\n@(require_results)\nread :: proc() -> Error { return .None }\n```\n\nProse after.\n"
	rf, err := parse_rule_file(src)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(rf.frontmatter, `id: "R3"`), rf.frontmatter)
	testing.expect(
		t,
		strings.contains(rf.frontmatter, `why: "it's \"quoted\": yes"`),
		rf.frontmatter,
	)
	testing.expect(t, strings.contains(rf.frontmatter, "blocking: true,"), rf.frontmatter)
	testing.expect(
		t,
		strings.contains(
			rf.frontmatter,
			`check: { kind: "require_attribute", attribute: "require_results" },`,
		),
		rf.frontmatter,
	)
	testing.expect_value(t, rf.prelude, "Error :: enum { None }")
	testing.expect_value(t, rf.fires, "read :: proc() -> Error { return .None }")
	testing.expect(t, strings.has_prefix(rf.silent, "@(require_results)"))
	testing.expect(
		t,
		strings.contains(rf.prose, "Prose before.") && strings.contains(rf.prose, "Prose after."),
	)
	testing.expect(
		t,
		strings.contains(rf.prose, "sample :: 1") && !strings.contains(rf.prose, "prelude"),
	)
	_, err2 := parse_rule_file("---\nid: R1\n")
	testing.expect(t, err2 != "")
	out := block_source("#+vet explicit-allocators\nx :: 1", "p")
	testing.expect_value(t, out, "#+vet explicit-allocators\npackage p\nx :: 1\n")
}

@(test)
test_quote_bare_values :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	testing.expect_value(
		t,
		quote_bare_values(
			`{ kind: banned_import, from: dependencies.may_import, roles: ["pure", edge], n: 3, ok: true }`,
		),
		`{ kind: "banned_import", from: "dependencies.may_import", roles: ["pure", "edge"], n: 3, ok: true }`,
	)
}
