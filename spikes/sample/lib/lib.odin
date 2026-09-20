package lib

// Vec is a 2D vector.
Vec :: struct {
	x, y: f32,
}
count: int
MAX :: 10

Error :: enum {
	None,
	Bad,
}

// must always be checked.
@(require_results)
must :: proc() -> Error {
	return .None
}

// open opens a thing.
@(require_results)
open :: proc(p: string) -> (h: int, err: Error) {
	return 0, .None
}

@(private)
hidden :: proc() {}
