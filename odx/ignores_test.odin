package odx

import "core:odin/ast"
import "core:odin/parser"
import "core:testing"

// Directive placement decides what an ignore covers; every case here was once a silent
// whole-file suppression or a swallowed second directive.
@(test)
test_ignore_targets :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	src := `package p
// odx:ignore x/R1 reason: own line targets the next code line

// still a comment
a := 1
b := 2 // odx:ignore x/R1 reason: end of line targets itself
c := "//" // odx:ignore x/R1 reason: a slash pair inside a string is code
// odx:ignore x/R1 reason: first // odx:ignore x/R2 reason: second on one line
// odx:ignore x/R1 reason: trailing directive with nothing after it
`
	f := ast.File {
		src      = src,
		fullpath = "p/p.odin",
	}
	ps := parser.default_parser()
	testing.expect(t, parser.parse_file(&ps, &f))
	rb: Rulebook
	append(&rb.topics, Topic{name = "x", rules = {{id = "R1"}, {id = "R2"}}})
	r: Report
	igs: [dynamic]Ignore
	collect_ignores(&r, &rb, &f, "p/p.odin", &igs)
	want := []int{5, 6, 7, 9} // target line per accepted directive, in order
	if testing.expect_value(t, len(igs), len(want)) {
		for ig, i in igs {testing.expectf(t, ig.target == want[i], "directive on line %d targets %d, want %d", ig.line, ig.target, want[i])}
	}
	if testing.expect_value(t, len(r.violations), 1) {
		testing.expect_value(t, r.violations[0].line, 8)
		testing.expect_value(t, r.violations[0].message, "one odx:ignore per line")
	}
}
