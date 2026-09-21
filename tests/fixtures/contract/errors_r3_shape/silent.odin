package errors_r3_shape

Mode :: enum {
	Fast,
	Slow,
}

Shape :: union #no_nil {
	int,
	f32,
}

@(require_results)
check_ok :: proc(x: int) -> Status {
	return .Bad if x < 0 else .Ok
}

// an enum with no None/Ok variant and a #no_nil union are values, not errors
mode :: proc(x: int) -> Mode {
	return .Fast if x < 0 else .Slow
}

shape :: proc(x: int) -> Shape {
	return x
}
