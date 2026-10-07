package app

import "base:intrinsics"

ORD :: intrinsics.type_is_ordered

ord :: intrinsics.type_is_ordered

Elem_Of :: intrinsics.type_elem_type

elem_of :: intrinsics.type_elem_type

Kind_Of :: type_of

kind_of :: type_of

is_ordered :: proc() -> bool {
	first: elem_of([]int)
	second: kind_of(first)
	return ord(type_of(second))
}
