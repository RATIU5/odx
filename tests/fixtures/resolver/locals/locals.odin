// One alias per row of the resolver's locals table. The resolver test names the aliases that get a
// `name-case` finding, so this file needs only to parse.
package locals

import "core:c"

Marker :: distinct int

sized :: proc($N: int, $T: typeid, items: [$M]$E, flag: bool, value: any) -> (total: int) {
	from_type :: T
	From_Type :: T
	from_value :: N
	FROM_VALUE :: N
	from_length :: M
	from_elem :: E
	from_param :: flag
	from_result :: total
	early :: later
	later :: 5
	before_variable :: Marker
	Marker := 0
	after_variable :: Marker
	for item in items {
		from_loop :: item
	}
	switch v in value {
	case int:
		from_switch :: v
	}
	nested := proc() {
		from_outer :: From_Type
		From_Outer :: From_Type
		from_outer_value :: FROM_VALUE
	}
	return
}

param :: struct {}
result :: struct {}
local :: struct {}
loop :: struct {}
choice :: struct {}
counter :: struct {}
POLY :: 5
SIZE :: struct {}

// A nested literal sees the enclosing procedure's constants, `$` parameters and static variables.
// Its other variables, parameters and results are out of scope there, so the names reach the
// package's symbols.
hidden :: proc(param: int, c: int, $POLY: typeid, $SIZE: int, value: any) -> (result: int) {
	local := 0
	@(static) counter := 0
	DEPTH :: 3
	own_import :: c.ulong
	for loop in 0 ..< 1 {
	}
	switch choice in value {
	}
	inner := proc() {
		via_param :: param
		via_result :: result
		via_local :: local
		via_loop :: loop
		via_choice :: choice
		via_static :: counter
		via_poly :: POLY
		via_size :: SIZE
		via_import :: c.ulong
		DEPTH := 1.5
		innermost := proc() {
			via_middle :: DEPTH
		}
	}
	return
}
