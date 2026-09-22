package odx

import "core:odin/ast"
import "core:odin/parser"
import "core:testing"

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

@(test)
test_pattern_package_scope_containers :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	f := ast.File {
		fullpath = "/sample/probe.odin",
		src      = `package sample
import "core:fmt"
constant :: 42
direct: int
first, second: int
@(thread_local)
threaded: int
when true {
	conditional: int
	foreign import libc "system:c"
	foreign libc {
		getchar :: proc() -> i32 ---
		external: i32
	}
	visible :: proc() {}
	@(private)
	hidden :: proc() {}
} else when false {
	other: int
} else {
	inactive: int
}
outer :: proc() {
	local: int
	when true {local_branch: int; _ = local_branch}
	inner :: proc() {nested: int; _ = nested}
	_ = local
}
`,
	}
	ps := parser.default_parser()
	testing.expect(t, parser.parse_file(&ps, &f))
	p := Package {
		files = {&f},
		role  = "pure",
	}
	Case :: struct {
		spec:     Check_Spec,
		subjects: []string,
	}
	cases := []Case {
		{
			spec = {kind = .pattern, match = "decl", at = "package_scope", mutable = true},
			subjects = {
				"direct",
				"first",
				"threaded",
				"conditional",
				"external",
				"other",
				"inactive",
			},
		},
		{spec = {kind = .pattern, match = "foreign"}, subjects = {"libc", "libc"}},
		{spec = {kind = .pattern, match = "import", name = "core:*"}, subjects = {"core:fmt"}},
		{
			spec = {kind = .pattern, match = "proc"},
			subjects = {"getchar", "visible", "hidden", "outer"},
		},
		{
			spec = {kind = .pattern, match = "proc", exported = true},
			subjects = {"getchar", "visible", "outer"},
		},
	}
	for tc in cases {
		r := Rule {
			check = tc.spec,
		}
		a := Active_Rule{"local/R1", &r}
		c := Ctx {
			root = "/sample",
			r    = new(Report),
		}
		check_pattern(&c, &p, &a)
		testing.expect_value(t, len(c.r.violations), len(tc.subjects))
		for v, i in c.r.violations {
			if i < len(tc.subjects) {testing.expect_value(t, v.subject, tc.subjects[i])}
			testing.expect_value(t, v.file, "probe.odin")
			testing.expect(t, v.line > 0 && v.col > 0)
		}
	}
}
