package odx

import "core:odin/ast"
import "core:odin/parser"
import "core:testing"

// The proc filters behind `match: proc`: exported-ness from attributes, the parameter at an
// index by name count, the type identifier through pointers and selectors.
@(test)
test_pattern_proc_filters :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	src := `package p
import "core:os"
Ctx :: struct {}
a :: proc(c: ^Ctx) {}
b :: proc(n: int, c: os.Ctx) {}
@(private) c :: proc(c: Ctx) {}
@(private = "file") d :: proc() {}
e :: proc(x, y: int, c: Ctx) {}
`
	f := ast.File {
		src      = src,
		fullpath = "p/p.odin",
	}
	ps := parser.default_parser()
	testing.expect(t, parser.parse_file(&ps, &f))
	got := make(map[string][2]bool) // name -> (private, has Ctx at index 0)
	for d in f.decls {
		vd, ok := d.derived.(^ast.Value_Decl)
		if !ok || len(vd.values) != 1 {continue}
		pl, is_proc := vd.values[0].derived.(^ast.Proc_Lit)
		if !is_proc {continue}
		got[ident_name(vd.names[0])] = {is_private(vd), has_param(pl.type, 0, "Ctx")}
	}
	testing.expect_value(t, got["a"], [2]bool{false, true})
	testing.expect_value(t, got["b"], [2]bool{false, false})
	testing.expect_value(t, got["c"], [2]bool{true, true})
	testing.expect_value(t, got["d"], [2]bool{true, false})
	testing.expect_value(t, got["e"], [2]bool{false, false})
	e := f.decls[len(f.decls) - 1].derived.(^ast.Value_Decl)
	testing.expect(t, has_param(e.values[0].derived.(^ast.Proc_Lit).type, 2, "Ctx"))
}
