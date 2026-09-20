#+vet explicit-allocators !shadowing
package pure

double :: proc(x: int) -> int {
	return x * 2
}
