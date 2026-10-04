package app

import "base:intrinsics"

// odx:ignore line-length a long where clause
Bar :: union($T: typeid)
	where intrinsics.type_is_numeric(T), intrinsics.type_is_numeric(T), intrinsics.type_is_numeric(T) {
	T, // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
}

_ :: Bar(int)
