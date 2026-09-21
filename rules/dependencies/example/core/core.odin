#+vet explicit-allocators
package core

// A pure package: values in, values out, no globals, no I/O.

MAX_HP :: 100

World :: struct {
	tick: int,
	hp:   int,
}

Input :: struct {
	damage: int,
}

step :: proc(w: World, input: Input) -> World {
	w := w
	w.tick += 1
	w.hp = max(0, min(MAX_HP, w.hp - input.damage))
	return w
}
