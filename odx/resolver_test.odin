package odx

import "core:mem/virtual"
import "core:strings"
import "core:testing"

@(private = "file")
FIXTURES :: "tests/fixtures/resolver"

@(private = "file")
FIXTURE_PACKAGES := [?]string{"lib", "locals", "shapes", "unfollowed"}

// Allocates with `context.allocator`, which each test sets to an arena.
@(private = "file")
init_fixture_resolver :: proc(r: ^Resolver) {
	universe, _ := universe_for(SUPPORTED_COMPILERS[0])
	resolver_init(r, strings.trim_right(ODIN_ROOT, "/"), nil, universe, context.allocator)
}

@(private = "file")
fixture_dir :: proc(name: string) -> string {
	return real_root(strings.concatenate({FIXTURES, "/", name}), context.allocator)
}

@(test)
every_supported_compiler_has_a_universe :: proc(t: ^testing.T) {
	for compiler in SUPPORTED_COMPILERS {
		universe, found := universe_for(compiler)
		testing.expectf(t, found, "no universe table for %s", compiler)
		testing.expectf(
			t,
			len(universe.builtin) > 0 && len(universe.intrinsics) > 0,
			"the universe table for %s is empty",
			compiler,
		)
	}
}

// What `tests/fixtures/resolver/shapes` declares, one name per row of the expression table.
@(private = "file", rodata)
SHAPE_KINDS := [?]Universe_Entry {
	{"LIMIT", .Value},
	{"TABLE", .Variable},
	{"state", .Variable},
	{"Color", .Type},
	{"Local_Type", .Type},
	{"package_alias", .Type},
	{"universe_type", .Type},
	{"universe_value", .Value},
	{"universe_proc", .Proc},
	{"undeclared", .Unknown},
	{"import_type", .Type},
	{"import_proc", .Proc},
	{"import_value", .Value},
	{"import_poly", .Poly_Type},
	{"import_variable", .Variable},
	{"import_missing_name", .Unknown},
	{"import_cycle", .Type},
	{"import_round_trip", .Type},
	{"builtin_selector", .Type},
	{"intrinsics_selector", .Type_Proc},
	{"intrinsics_type_or_value", .Unknown},
	{"through_core", .Type},
	{"unresolved_import", .Unknown},
	{"foreign_selector", .Unknown},
	{"field_selector", .Variable},
	{"enum_selector", .Variable},
	{"poly_param_selector", .Variable},
	{"nested_selector", .Variable},
	{"index_expr", .Variable},
	{"paren", .Type},
	{"tagged", .Type},
	{"poly_struct", .Poly_Type},
	{"poly_union", .Poly_Type},
	{"plain_struct", .Type},
	{"plain_union", .Type},
	{"enum_type", .Type},
	{"bit_set_type", .Type},
	{"bit_field_type", .Type},
	{"distinct_type", .Type},
	{"proc_type", .Type},
	{"pointer_type", .Type},
	{"multi_pointer_type", .Type},
	{"array_type", .Type},
	{"dynamic_array_type", .Type},
	{"map_type", .Type},
	{"matrix_type", .Type},
	{"typeid_type", .Type},
	{"proc_lit", .Proc},
	{"proc_group", .Proc},
	{"directive_call", .Value},
	{"type_call", .Value},
	{"proc_call", .Value},
	{"variable_call", .Value},
	{"value_call", .Value},
	{"poly_call", .Type},
	{"type_proc_call", .Type},
	{"intrinsic_type_call", .Type},
	{"intrinsic_type_or_value_call", .Unknown},
	{"unknown_call", .Unknown},
	{"paren_callee", .Value},
	{"ternary_same", .Type},
	{"ternary_differs", .Unknown},
	{"ternary_if", .Value},
	{"basic_lit", .Value},
	{"comp_lit", .Value},
	{"unary", .Value},
	{"binary", .Value},
	{"cast_expr", .Value},
	{"slice_expr", .Value},
	{"deref", .Value},
	{"or_else_expr", .Value},
	{"implicit_selector", .Value},
	{"basic_directive", .Unknown},
	{"cycle_a", .Unknown},
	{"cycle_b", .Unknown},
	{"beside_cycle", .Unknown},
	{"variable", .Variable},
	{"typed_constant", .Value},
	{"typed_alias", .Value},
	{"when_same", .Type},
	{"when_differs", .Unknown},
	{"foreign_proc", .Proc},
	{"foreign_variable", .Variable},
	{"platform_same", .Type},
	{"platform_differs", .Unknown},
	{"test_name", .Value},
}

@(test)
each_expression_shape_resolves_to_its_kind :: proc(t: ^testing.T) {
	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	r: Resolver
	init_fixture_resolver(&r)
	symbols := package_symbols(&r, fixture_dir("shapes"))
	for row in SHAPE_KINDS {
		kind, declared := symbols[row.name]
		testing.expectf(
			t,
			declared && kind == row.kind,
			"%s is %v (declared %v), want %v",
			row.name,
			kind,
			declared,
			row.kind,
		)
	}
	// The hidden, ignored and unparsable files declare the rest, and discovery reads none of them.
	testing.expectf(
		t,
		len(symbols) == len(SHAPE_KINDS),
		"the package has %d symbols, want %d",
		len(symbols),
		len(SHAPE_KINDS),
	)
}

@(test)
a_package_resolves_alike_through_the_walk_and_the_loader :: proc(t: ^testing.T) {
	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	walked: Resolver
	init_fixture_resolver(&walked)
	result: Result
	discover(FIXTURES, {}, &walked, &result, context.allocator)

	for name in FIXTURE_PACKAGES {
		dir := fixture_dir(name)
		loaded: Resolver
		init_fixture_resolver(&loaded)
		want := package_symbols(&loaded, dir)

		pkg, cached := walked.cache[dir]
		if !testing.expectf(t, cached, "the walk didn't load %s under its real path", name) {
			continue
		}
		testing.expectf(t, pkg.parsed == nil, "%s still holds its declarations", name)
		expect_same_symbols(t, name, pkg.symbols, want)
	}
}

@(test)
symbols_do_not_depend_on_the_load_order :: proc(t: ^testing.T) {
	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	forward, backward: Resolver
	init_fixture_resolver(&forward)
	init_fixture_resolver(&backward)
	for name in FIXTURE_PACKAGES {
		package_symbols(&forward, fixture_dir(name))
	}
	#reverse for name in FIXTURE_PACKAGES {
		package_symbols(&backward, fixture_dir(name))
	}
	for name in FIXTURE_PACKAGES {
		dir := fixture_dir(name)
		expect_same_symbols(
			t,
			name,
			package_symbols(&forward, dir),
			package_symbols(&backward, dir),
		)
	}
	// Resolving `shapes.import_cycle` loads `lib`, whose `Through_Back` names it back. Neither is
	// in a cycle, whichever package loads first.
	for r in ([]^Resolver{&forward, &backward}) {
		kind := package_symbols(r, fixture_dir("lib"))["Through_Back"]
		testing.expectf(t, kind == .Type, "lib.Through_Back is %v, want Type", kind)
	}
}

@(private = "file")
expect_same_symbols :: proc(t: ^testing.T, name: string, got, want: Package_Symbols) {
	testing.expectf(t, len(got) == len(want), "%s: %d symbols, want %d", name, len(got), len(want))
	for symbol, kind in want {
		got_kind, declared := got[symbol]
		testing.expectf(
			t,
			declared && got_kind == kind,
			"%s.%s is %v (declared %v), want %v",
			name,
			symbol,
			got_kind,
			declared,
			kind,
		)
	}
}

@(test)
an_alias_of_a_local_takes_the_case_of_the_locals_table :: proc(t: ^testing.T) {
	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	want := []string {
		"type 'from_type' isn't Ada_Case",
		"constant 'from_value' isn't SCREAMING_CASE",
		"constant 'from_length' isn't SCREAMING_CASE",
		"type 'from_elem' isn't Ada_Case",
		"constant 'early' isn't SCREAMING_CASE",
		"constant 'later' isn't SCREAMING_CASE",
		"type 'before_variable' isn't Ada_Case",
		"variable 'Marker' isn't snake_case",
		"type 'from_outer' isn't Ada_Case",
		"constant 'from_outer_value' isn't SCREAMING_CASE",
		"type 'param' isn't Ada_Case",
		"type 'result' isn't Ada_Case",
		"type 'local' isn't Ada_Case",
		"type 'loop' isn't Ada_Case",
		"type 'choice' isn't Ada_Case",
		"type 'counter' isn't Ada_Case",
		"type 'via_param' isn't Ada_Case",
		"type 'via_result' isn't Ada_Case",
		"type 'via_local' isn't Ada_Case",
		"type 'via_loop' isn't Ada_Case",
		"type 'via_choice' isn't Ada_Case",
		"type 'via_poly' isn't Ada_Case",
		"constant 'via_size' isn't SCREAMING_CASE",
		"type 'via_import' isn't Ada_Case",
		"variable 'DEPTH' isn't snake_case",
		"constant 'via_middle' isn't SCREAMING_CASE",
	}
	expect_name_case_messages(t, "locals", want)
}

@(test)
an_alias_through_an_unfollowed_import_gets_no_finding :: proc(t: ^testing.T) {
	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_name_case_messages(t, "unfollowed", {"constant 'limit' isn't SCREAMING_CASE"})
}

// Discovers the fixtures and compares the `name-case` messages of the package in `dir`, in order.
// Allocates with `context.allocator`.
@(private = "file")
expect_name_case_messages :: proc(t: ^testing.T, dir: string, want: []string) {
	r: Resolver
	init_fixture_resolver(&r)
	result: Result
	packages := discover(FIXTURES, {}, &r, &result, context.allocator)
	got := make([dynamic]string)
	for pkg in packages {
		if pkg.dir != dir {
			continue
		}
		for file in pkg.files {
			for finding in file.findings {
				if finding.rule == .Name_Case {
					append(&got, finding.message)
				}
			}
		}
	}
	testing.expectf(t, len(got) == len(want), "%d findings, want %d: %v", len(got), len(want), got)
	for message, i in want {
		if i < len(got) {
			testing.expectf(t, got[i] == message, "finding %d is %q, want %q", i, got[i], message)
		}
	}
}
