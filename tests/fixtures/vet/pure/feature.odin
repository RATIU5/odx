#+feature using-stmt // want: odx/feature-optout allocators/R1
package pure

quad :: proc(x: int) -> int {
	return x * 4
}
