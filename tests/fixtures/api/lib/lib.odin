package lib

Error :: enum {
	None,
	Bad,
}

Vec :: struct {
	x, y: f32,
}

Shape :: union {
	Vec,
	f32,
}

MAX :: 10

Handle :: distinct int

@(require_results)
open :: proc(name: string, flags: bit_set[Error] = {}) -> (h: Handle, err: Error) {
	return 1, .None
}

@(deprecated = "use open")
old_open :: proc(name: string) -> Handle {
	return 1
}

sum :: proc(xs: ..int) -> int {
	n := 0
	for x in xs {n += x}
	return n
}

scale :: proc {
	scale_vec,
	scale_f,
}
scale_vec :: proc(v: ^Vec, k: f32) {v.x *= k; v.y *= k}
scale_f :: proc(f: f32, k: f32) -> f32 {return f * k}

@(private)
hidden :: proc() {}

lookup :: proc(m: map[string][]Vec, k: string) -> ([]Vec, bool) #optional_ok {
	v, ok := m[k]
	return v, ok
}
