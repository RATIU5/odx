package lib

import "../shapes"

LIMIT :: 5

Id :: distinct int

Box :: struct($T: typeid) {
	item: T,
}

counter := 0

next :: proc(id: Id) -> Id {
	return id + 1
}

// The two packages import each other, which the compiler rejects and the resolver must survive.
Back :: shapes.Local_Type

Round_Trip :: shapes.import_type

// `shapes.import_cycle` is `lib.Back`, so resolving it loads this package while it is unresolved.
// This name depends on it and is in no cycle.
Through_Back :: shapes.import_cycle
