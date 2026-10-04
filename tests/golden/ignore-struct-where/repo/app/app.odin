package app

import "base:intrinsics"

// odx:ignore line-length a long where clause
Foo :: struct($T: typeid)
	where intrinsics.type_is_numeric(T), intrinsics.type_is_numeric(T), intrinsics.type_is_numeric(T) {
	x: T, // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
}

_ :: Foo(int)
