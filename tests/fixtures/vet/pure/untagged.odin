#+vet !unused // want: odx/vet-disable allocators/R1
package pure

triple :: proc(x: int) -> int {
	return x * 3
}
