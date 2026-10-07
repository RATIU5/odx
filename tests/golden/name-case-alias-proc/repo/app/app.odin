package app

helper :: proc() {}

helper_int :: proc(x: int) -> int {
	return x
}

run :: helper

Run :: helper

either :: proc {
	helper,
	helper_int,
}

any_of :: either

Any_Of :: either

length :: len

Length :: len
