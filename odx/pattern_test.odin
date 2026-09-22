package odx

import "core:odin/ast"
import "core:odin/parser"
import "core:strings"
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

@(test)
test_pattern_if_do_syntax_boundary :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	Case :: struct {
		body:     string,
		findings: int,
	}
	cases := []Case {
		{"if ready {return}", 1},
		{"if ready {process()}", 1},
		{"if ready {(process())}", 1},
		{"if ready {process();}", 1},
		{"when false {if ready {process()}}", 1},
		{"if ready {value = 1}", 1},
		{"if ready {a, b = get_pair()}", 1},
		{"if ready {process(first(), second())}", 1},
		{"if ready {\n// preserve comment\nreturn\n}", 1},
		{"if ready {process(\n1,\n2,\n)}", 1},
		{"if ready do return", 0},
		{"if ready do process()", 0},
		{"if ready do value = 1", 0},
		{"if ready {process(); process()}", 0},
		{"if ready {value := 1}", 0},
		{"if ready {defer process()}", 0},
		{"if ready {for ready {process()}}", 0},
		{"if ready {}", 0},
		{"if ready {return} else {return}", 0},
		{"if ready {return} else if other {return}", 0},
		{"if ready {process()} else if other {process()} else {process()}", 0},
		{"if ready {if other {process()}}", 1},
		{"inner := proc() {if ready {return}}", 1},
		{"text := `if ready {process()}`", 0},
		{"// if ready {process()}\n", 0},
	}
	for tc in cases {
		f := ast.File {
			fullpath = "/sample/probe.odin",
			src      = strings.concatenate(
				{"package sample\nrun :: proc() {\n", tc.body, "\n}\n"},
			),
		}
		f.node.derived = &f
		ps := parser.default_parser()
		if !testing.expect(t, parser.parse_file(&ps, &f), tc.body) {continue}
		p := Package {
			files = {&f},
		}
		for severity in Severity {
			r := Rule {
				check = {kind = .pattern, match = "if"},
				severity = severity,
			}
			a := Active_Rule{"local/IF", &r}
			c := Ctx {
				root = "/sample",
				r    = new(Report),
			}
			check_pattern(&c, &p, &a)
			testing.expect(t, len(c.r.violations) == tc.findings, tc.body)
			for finding in c.r.violations {
				testing.expect_value(t, finding.severity, severity)
				testing.expect_value(t, finding.file, "probe.odin")
				testing.expect(t, finding.line >= 3 && finding.col >= 1)
				testing.expect(t, strings.contains(finding.message, "if CONDITION do STATEMENT"))
			}
		}
	}
}
