package odx

import "core:mem/virtual"
import "core:strings"
import "core:testing"

// A shape of nesting that `core:odin/parser` recurses on, as `open` repeated, then `middle`, then
// `close` repeated. `compiler_dies_at` is the smallest depth at which the pinned compiler's
// `odin check` ended by a signal when it was bisected.
@(private = "file")
Nesting_Shape :: struct {
	name:                string,
	head, open:          string,
	middle, close, tail: string,
	compiler_dies_at:    int,
}

@(private = "file", rodata)
NESTING_SHAPES := [?]Nesting_Shape {
	{"parentheses", "X :: ", "(", "1", ")", "\n", 3285},
	{"else if", "f :: proc(c: bool) {\n\tif c {\n\t}", " else if c {\n\t}", "", "", "\n}\n", 820},
	{"unary operators", "X :: ", "- ", "1", "", "\n", 8655},
	{"pointers", "X :: ", "^", "int", "", "\n", 3383},
	{"ternaries", "f :: proc(c: bool) -> int {\n\treturn ", "c ? 1 : ", "0", "", "\n}\n", 1040},
	{"procedure literals", "f :: proc() {\n", "p := proc() {\n", "", "}\n", "}\n", 1479},
	{"binary operators", "X :: ", "1 + ", "1", "", "\n", 4750},
	{"array types", "X :: ", "[1]", "int", "", "\n", 3871},
	{"250 pointers per parenthesis", "x: ", PTR250 + "(", "int", ")", "\n", 65},
	{"map types", "x: ", "map[int]", "int", "", "\n", 3871},
	{"distinct types", "X :: ", "distinct ", "int", "", "\n", 3578},
	{"procedure results", "x: ", "proc() -> ", "int", "", "\n", 3236},
}

@(private = "file")
PTR250 :: PTR50 + PTR50 + PTR50 + PTR50 + PTR50

@(private = "file")
PTR50 :: "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"

// odx must never end on a file the compiler accepts, so the work stack has to carry the parser
// well past the depth that ends the compiler. Twice that depth is the margin the stack was sized
// against.
@(test)
the_work_stack_carries_the_parser_twice_as_deep_as_the_compiler_goes :: proc(t: ^testing.T) {
	failed := run_on_work_stack(proc() -> int {
		arena: virtual.Arena
		ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
		defer virtual.arena_destroy(&arena)
		context.allocator = virtual.arena_allocator(&arena)
		failed := 0
		for shape, i in NESTING_SHAPES {
			depth := 2 * shape.compiler_dies_at
			src := strings.concatenate(
				{
					"package a\n\n",
					shape.head,
					strings.repeat(shape.open, depth),
					shape.middle,
					strings.repeat(shape.close, depth),
					shape.tail,
				},
			)
			if _, failure := parse_source(src, context.allocator); failure != nil {
				failed |= 1 << uint(i)
			}
			virtual.arena_free_all(&arena)
		}
		return failed
	})
	for shape, i in NESTING_SHAPES {
		testing.expectf(t, failed & (1 << uint(i)) == 0, "%s didn't parse", shape.name)
	}
}

@(test)
run_on_work_stack_returns_what_the_work_returns :: proc(t: ^testing.T) {
	testing.expect_value(t, run_on_work_stack(proc() -> int {return 7}), 7)
}

@(test)
parse_source_reports_a_file_without_a_package_clause :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := []struct {
		name, src: string,
		offset:    int,
	} {
		{"a 0-byte file, for which the parser reports nothing", "", 0},
		{"a file of blank lines", "\n\n", 2},
		{"a comment-only file", "// note\n", 8},
	}
	for c in cases {
		_, parse_error := parse_source(c.src, context.allocator)
		e, found := parse_error.?
		testing.expectf(
			t,
			found && e.offset == c.offset && e.message == NO_PACKAGE_MESSAGE,
			"%s: got %v",
			c.name,
			parse_error,
		)
	}
}
