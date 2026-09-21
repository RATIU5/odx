#+vet explicit-allocators
package dependencies_r3

Counter :: struct {
	count: int,
}

bump_counter :: proc(c: ^Counter) -> int {
	c.count += 1
	return c.count
}
