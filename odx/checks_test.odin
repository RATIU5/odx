package odx

import "core:odin/ast"
import "core:odin/parser"
import "core:testing"

@(test)
test_feature_optouts_require_nonempty_same_line_reason :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	for example in ([]struct {
		source: string,
		findings: int,
	}{
		{"#+feature dynamic-literals\npackage sample\n", 1},
		{"#+feature dynamic-literals // reason:\npackage sample\n", 1},
		{"#+feature dynamic-literals // reason:   \t\npackage sample\n", 1},
		{"// reason: Legacy syntax is intentional.\n#+feature dynamic-literals\npackage sample\n", 1},
		{"#+feature dynamic-literals // reason: Legacy syntax is intentional.\npackage sample\n", 0},
	}) {
		f := ast.File{src = example.source, fullpath = "/sample/main.odin"}
		ps := parser.default_parser()
		testing.expect(t, parser.parse_file(&ps, &f))
		cfg := default_config()
		r: Report
		c := Ctx{root = "/sample", cfg = &cfg, r = &r}
		check_vet_disables(&c, &f)
		testing.expect_value(t, len(r.violations), example.findings)
		for v in r.violations {testing.expect_value(t, v.rule, "odx/feature-optout")}
	}
}
