#+vet explicit-allocators
package core

Handle :: distinct int

Error :: enum {
	None,
	Not_Found,
	Permission,
}

Config :: struct {
	name: string,
}

// open is the fallible primitive: an error type last, and the attribute so a
// dropped result is a compile error.
@(require_results)
open :: proc(path: string) -> (h: Handle, err: Error) {
	if path == "" {
		return 0, .Not_Found
	}
	return Handle(len(path)), .None
}

close :: proc(h: Handle) {
	_ = h
}

// load propagates with or_return and cleans up with defer.
@(require_results)
load :: proc(path: string) -> (cfg: Config, err: Error) {
	h := open(path) or_return
	defer close(h)
	cfg.name = path
	return cfg, .None
}
