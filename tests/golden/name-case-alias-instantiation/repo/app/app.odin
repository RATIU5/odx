package app

import "base:intrinsics"
import "core:sync/chan"

Vec :: struct($N: int, $T: typeid) {
	items: [N]T,
}

Event :: struct {
	id: int,
}

Vec3f :: Vec(3, f32)

vec3f :: Vec(3, f32)

Update_Channel :: chan.Chan(Event)

update_channel :: chan.Chan(Event)

Maybe_Int :: Maybe(int)

Element :: intrinsics.type_elem_type([]int)

element :: intrinsics.type_elem_type([]int)

Chan :: chan.Chan

channel :: chan.Chan
