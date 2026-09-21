package errors_r5

import "core:os"

Error :: enum {
	None,
	Read_Failed,
}

@(require_results)
read_wrapped :: proc(path: string) -> (data: []byte, err: Error) {
	d, oerr := os.read_entire_file(path, context.allocator)
	if oerr != nil {return nil, .Read_Failed}
	return d, .None
}
