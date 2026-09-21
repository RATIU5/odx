package errors_r5

import "core:os"

@(require_results)
read :: proc(path: string) -> (data: []byte, err: os.Error) { // want: errors/R5
	return os.read_entire_file(path, context.allocator)
}
