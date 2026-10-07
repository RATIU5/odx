package app

import "core:os"

Color :: enum {
	Red,
	Green,
}

write :: os.write

Write :: os.write

Failure :: os.Error

failure :: os.Error

default_color :: Color.Red

Vec :: struct($N: int, $T: typeid) {
	data: [N]T,
}

Vec3f :: Vec(3, f32)

Elem :: Vec3f.T

elem :: Vec3f.T

LENGTH :: Vec3f.N

length :: Vec3f.N
