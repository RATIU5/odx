package odx

import "core:mem/virtual"
import "core:odin/ast"
import "core:testing"

@(test)
code_line_prefix_sums_counts_only_lines_that_hold_code :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	cases := []struct {
		name:     string,
		src:      string,
		has_code: []bool,
	} {
		{"a line with only a brace", "package a\nf :: proc() {\n}\n", {true, true, true}},
		{
			"code with a trailing comment, then a comment alone",
			"package a\nA :: 1 // one\n// two\n",
			{true, true, false},
		},
		{
			"every line of a block comment",
			"package a\n/*\nb\n*/\nA :: 1\n",
			{true, false, false, false, true},
		},
		{
			"code after a block comment's end",
			"package a\nx := 0\n/* a\nb */ x += 1\n",
			{true, true, false, true},
		},
		{
			"a blank line and a line of spaces",
			"package a\n\n\t \nA :: 1\n",
			{true, false, false, true},
		},
	}
	for c in cases {
		file, failure := parse_source(c.src, context.allocator)
		if _, failed := failure.?; failed {
			testing.expectf(t, false, "%s: the source doesn't parse", c.name)
			continue
		}
		sums := code_line_prefix_sums(c.src, file.comments[:])
		if !testing.expectf(t, len(sums) > len(c.has_code), "%s: %d sums", c.name, len(sums)) {
			continue
		}
		testing.expectf(t, sums[0] == 0, "%s: the sums start at %d", c.name, sums[0])
		for want, i in c.has_code {
			got := sums[i + 1] - sums[i] == 1
			testing.expectf(t, got == want, "%s: line %d counted is %v", c.name, i + 1, got)
		}
	}
}

@(test)
open_proc_reports_a_literal_with_no_parent_at_its_proc_token :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	SRC :: "package a\nf :: proc() {\n}\n"
	file, _ := parse_source(SRC, context.allocator)
	decl := file.decls[0].derived.(^ast.Value_Decl)
	lit := decl.values[0].derived.(^ast.Proc_Lit)
	w := File_Walk {
		procs = make([dynamic]Proc_Frame, context.allocator),
	}
	open_proc(&w, lit, nil)
	testing.expect_value(t, w.procs[0].finding_pos, lit.type.tok.pos)
	pop(&w.procs)
	open_proc(&w, lit, decl)
	testing.expect_value(t, w.procs[0].finding_pos, decl.names[0].pos)
}
