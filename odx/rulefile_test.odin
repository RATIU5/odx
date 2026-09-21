package odx

import "core:strings"
import "core:testing"

@(test)
test_parse_rule_file :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	src := "---\nid: \"R3\",\nwhy: \"it's \\\"quoted\\\": yes\",\nblocking: true,\ncheck: { kind: \"require_attribute\", attribute: \"require_results\" },\n---\n\nProse before.\n\n```odin prelude\nError :: enum { None }\n```\n\n```odin fires\nread :: proc() -> Error { return .None }\n```\n\n```odin\nsample :: 1\n```\n\n```odin silent\n@(require_results)\nread :: proc() -> Error { return .None }\n```\n\nProse after.\n"
	rf, err := parse_rule_file(src)
	testing.expect_value(t, err, "")
	// the frontmatter is passed through untouched, wrapped as one object
	testing.expect(t, strings.has_prefix(rf.frontmatter, "{\nid: \"R3\","), rf.frontmatter)
	testing.expect(t, strings.has_suffix(rf.frontmatter, "},\n}"), rf.frontmatter)
	r: struct {
		id:       string,
		why:      string,
		blocking: bool,
		check:    struct {
			kind, attribute: string,
		},
	}
	errs: [dynamic]string
	_, ok := unmarshal_json5(rf.frontmatter, &r, "rule", nil, &errs)
	testing.expect(t, ok, strings.join(errs[:], "; "))
	testing.expect_value(t, r.why, `it's "quoted": yes`)
	testing.expect_value(t, r.check.attribute, "require_results")
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
	_, err2 := parse_rule_file("---\nid: \"R1\",\n")
	testing.expect(t, err2 != "")
	out := block_source("#+vet explicit-allocators\nx :: 1", "p")
	testing.expect_value(t, out, "#+vet explicit-allocators\npackage p\nx :: 1\n")
}
