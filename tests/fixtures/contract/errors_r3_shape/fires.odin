package errors_r3_shape

// no Error suffix anywhere: the shape alone makes these error types
Status :: enum {
	Ok,
	Bad,
}

Fault :: union {
	int,
}

check :: proc(x: int) -> Status { // want: errors/R3
	return .Bad if x < 0 else .Ok
}

probe :: proc(x: int) -> Fault { // want: errors/R3
	return x if x < 0 else nil
}
