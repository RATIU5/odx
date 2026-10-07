// One declaration per row of the resolver's expression table. The resolver test names the kind it
// expects for each, so this file needs only to parse.
package shapes

import "base:builtin"
import "base:intrinsics"
import "core:c"

import "shared:missing"

import "../lib"

foreign import libc "system:c"

LIMIT :: 5

TABLE := [?]int{1, 2}

state: struct {
	field: int,
	run:   proc(x: int) -> int,
}

Color :: enum {
	Red,
}

Local_Type :: struct {}

package_alias :: Local_Type
universe_type :: int
universe_value :: true
universe_proc :: len
undeclared :: nowhere

import_type :: lib.Id
import_proc :: lib.next
import_value :: lib.LIMIT
import_poly :: lib.Box
import_variable :: lib.counter
import_missing_name :: lib.nothing
import_cycle :: lib.Back
import_round_trip :: lib.Round_Trip
builtin_selector :: builtin.u8
intrinsics_selector :: intrinsics.type_elem_type
intrinsics_type_or_value :: intrinsics.type_polymorphic_record_parameter_value
through_core :: c.ulong
unresolved_import :: missing.Thing
foreign_selector :: libc.thing
field_selector :: state.field
enum_selector :: Color.Red
poly_param_selector :: poly_call.T
nested_selector :: lib.counter.field
index_expr :: TABLE[0]

paren :: (int)
tagged :: #row_major matrix[2, 2]f32

poly_struct :: struct($T: typeid) {
	item: T,
}
poly_union :: union($T: typeid) {
	T,
}
plain_struct :: struct {}
plain_union :: union {
	int,
}
enum_type :: enum {
	A,
}
bit_set_type :: bit_set[Color]
bit_field_type :: bit_field u8 {
	low: u8 | 4,
}
distinct_type :: distinct int
proc_type :: proc()
pointer_type :: ^int
multi_pointer_type :: [^]int
array_type :: [4]int
dynamic_array_type :: [dynamic]int
map_type :: map[string]int
matrix_type :: matrix[2, 2]f32
typeid_type :: typeid

proc_lit :: proc() {}
proc_group :: proc {
	proc_lit,
}

directive_call :: #config(SHAPES_LIMIT, 1)
type_call :: int(1)
proc_call :: len("abc")
variable_call :: state.run(1)
value_call :: LIMIT(1)
poly_call :: poly_struct(int)
type_proc_call :: type_of(state)
intrinsic_type_call :: intrinsics.type_elem_type([]int)
intrinsic_type_or_value_call :: intrinsics.type_polymorphic_record_parameter_value(
	poly_struct(int),
	0,
)
unknown_call :: nowhere(1)
paren_callee :: (int)(1)

ternary_same :: int when ODIN_OS == .Windows else i32
ternary_differs :: int when ODIN_OS == .Windows else 4
ternary_if :: 1 if ODIN_DEBUG else 2

basic_lit :: 5
comp_lit :: [2]int{1, 2}
unary :: -5
binary :: 1 + 2
cast_expr :: cast(int)5
slice_expr :: "abc"[1:]
deref :: pointer^
or_else_expr :: maybe_value.? or_else 0
implicit_selector :: .Red

basic_directive :: #file

cycle_a :: cycle_b
cycle_b :: cycle_a
beside_cycle :: cycle_a

variable := 5
typed_constant: int : 5
typed_alias: typeid : int

when ODIN_OS == .Windows {
	when_same :: int
	when_differs :: int
} else {
	when_same :: i32
	when_differs :: 5
}

foreign libc {
	foreign_proc :: proc() ---
	foreign_variable: int
}
