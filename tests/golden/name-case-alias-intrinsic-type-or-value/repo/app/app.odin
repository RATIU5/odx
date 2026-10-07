package app

import "base:intrinsics"

Vec :: struct($N: int, $T: typeid) {
	data: [N]T,
}

Elem :: intrinsics.type_polymorphic_record_parameter_value(Vec(3, f32), 1)

elem :: intrinsics.type_polymorphic_record_parameter_value(Vec(3, f32), 1)

COUNT :: intrinsics.type_polymorphic_record_parameter_value(Vec(3, f32), 0)

count :: intrinsics.type_polymorphic_record_parameter_value(Vec(3, f32), 0)

Param :: intrinsics.type_polymorphic_record_parameter_value

zero :: proc() -> (Elem, elem, [COUNT + count]int) {
	return 0, 0, {}
}
