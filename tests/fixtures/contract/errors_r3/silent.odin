package errors_r3

@(require_results)
read_checked :: proc(path: string) -> (data: []byte, err: Error) {
	return nil, .Not_Found if len(path) == 0 else .None
}
