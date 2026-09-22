package odx

import "core:odin/ast"
import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
source_fixture :: proc(t: ^testing.T, files: []struct {
		name, text: string,
	}) -> string {
	root, err := os.make_directory_temp("", "odx-source-*", context.allocator)
	testing.expect(t, err == nil)
	for f in files {
		testing.expect(
			t,
			os.write_entire_file(join({root, f.name}), transmute([]byte)f.text) == nil,
		)
	}
	return root
}

@(test)
test_source_loading_reports_incomplete_syntax :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	for source in ([]string{"broken :: 1", "package example\nbroken :: proc( {\n"}) {
		root := source_fixture(t, {{"broken.odin", source}})
		cfg := default_config()
		pkgs := load_packages(root, &cfg, {""})
		testing.expect_value(t, pkgs[0].parse_result.status, Evidence_Status.failed)
		testing.expect(t, len(pkgs[0].diags) > 0)
		testing.expect_value(t, len(pkgs[0].files), 1)
		os.remove_all(root)
	}
}

@(test)
test_source_loading_reports_package_mismatch :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root := source_fixture(t, {{"a.odin", "package first"}, {"b.odin", "package second"}})
	defer os.remove_all(root)
	cfg := default_config()
	pkgs := load_packages(root, &cfg, {""})
	testing.expect_value(t, pkgs[0].parse_result.status, Evidence_Status.failed)
	testing.expect_value(t, len(pkgs[0].diags), 1)
	testing.expect(t, strings.contains(pkgs[0].diags[0].msg, "expected 'first', got 'second'"))
}

@(test)
test_source_selection_includes_inactive_and_generated_files :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root := source_fixture(
		t,
		{
			{"main.odin", "package example\na :: 1"},
			{"platform_windows.odin", "package example\nb :: unavailable_on_host"},
			{"ignored.odin", "#+ignore\npackage example\nc :: ignored_by_compiler"},
			{"generated.odin", "// Code generated. DO NOT EDIT.\npackage example\nd :: 1"},
			{"example_test.odin", "package example\ne :: 1"},
			{"blank.odin", " \n\t"},
		},
	)
	defer os.remove_all(root)
	cfg := default_config()
	pkgs := load_packages(root, &cfg, {""})
	testing.expect_value(t, pkgs[0].parse_result.status, Evidence_Status.complete)
	testing.expect_value(t, len(pkgs[0].files), 5)
	for f, i in pkgs[0].files {
		if i > 0 {testing.expect(t, pkgs[0].files[i - 1].fullpath < f.fullpath)}
	}
}

@(test)
test_source_ast_preserves_policy_evidence :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root := source_fixture(
		t,
		{
			{
				"evidence.odin",
				`#+vet explicit-allocators
package example
import renamed "core:fmt"
// Declaration documentation.
@(private)
outer :: proc() {
	nested :: proc() {renamed.println("nested")}
	nested()
}
a, b: int
Alias :: int
when false {
	inactive :: proc() {renamed.println("inactive")}
} else {
	active :: 1
}
foreign import libc "system:c"
foreign libc { puts :: proc(s: cstring) -> i32 --- }
`,
			},
		},
	)
	defer os.remove_all(root)
	cfg := default_config()
	pkgs := load_packages(root, &cfg, {""})
	testing.expect_value(t, pkgs[0].parse_result.status, Evidence_Status.complete)
	f := pkgs[0].files[0]
	testing.expect_value(t, len(f.tags), 1)
	testing.expect_value(t, len(f.comments), 1)
	testing.expect_value(t, f.imports[0].name.text, "renamed")
	outer := f.decls[1].derived.(^ast.Value_Decl)
	testing.expect_value(t, len(outer.attributes), 1)
	testing.expect(t, outer.docs != nil)
	grouped := f.decls[2].derived.(^ast.Value_Decl)
	testing.expect_value(t, len(grouped.names), 2)
	testing.expect(t, grouped.is_mutable)
	Counts :: struct {
		procs, calls, whens, foreign_imports, foreign_blocks: int,
	}
	counts: Counts
	visitor := ast.Visitor {
		data = &counts,
		visit = proc(v: ^ast.Visitor, n: ^ast.Node) -> ^ast.Visitor {
			if n == nil {return nil}
			c := cast(^Counts)v.data
			#partial switch _ in n.derived {
			case ^ast.Proc_Lit:
				c.procs += 1
			case ^ast.Call_Expr:
				c.calls += 1
			case ^ast.When_Stmt:
				c.whens += 1
			case ^ast.Foreign_Import_Decl:
				c.foreign_imports += 1
			case ^ast.Foreign_Block_Decl:
				c.foreign_blocks += 1
			}
			return v
		},
	}
	ast.walk(&visitor, f)
	testing.expect_value(t, counts.procs, 4)
	testing.expect_value(t, counts.calls, 3)
	testing.expect_value(t, counts.whens, 1)
	testing.expect_value(t, counts.foreign_imports, 1)
	testing.expect_value(t, counts.foreign_blocks, 1)
}

@(test)
test_source_loading_reports_collection_failure :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root := source_fixture(t, {})
	defer os.remove_all(root)
	testing.expect(t, os.make_directory(join({root, "unreadable.odin"})) == nil)
	cfg := default_config()
	pkgs := load_packages(root, &cfg, {""})
	testing.expect_value(t, pkgs[0].parse_result.status, Evidence_Status.failed)
	testing.expect(t, strings.contains(pkgs[0].parse_result.reason, "collect"))
}
