#+vet explicit-allocators
package dependencies_r4

magnitude_pure :: proc(x: i32) -> i32 {
	return x if x >= 0 else -x
}
