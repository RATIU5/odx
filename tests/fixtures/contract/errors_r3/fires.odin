package errors_r3

Error :: enum {
	None,
	Not_Found,
}

read :: proc(path: string) -> (data: []byte, err: Error) { // want: errors/R3
	return nil, .Not_Found if len(path) == 0 else .None
}
