package app

DoThing :: proc() {}

Do_Thing :: proc() {}

DO_THING :: proc() {}

do_thing :: proc() {}

do_2nd_thing :: proc(x: int) {}

Things :: proc {
	do_thing,
	do_2nd_thing,
}

things :: proc {
	do_thing,
	do_2nd_thing,
}

outer :: proc() -> int {
	AddOne :: proc(x: int) -> int {
		return x + 1
	}
	add_two :: proc(x: int) -> int {
		return x + 2
	}
	return AddOne(add_two(0))
}
