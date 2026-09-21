#+feature using-stmt // reason: legacy refactor in progress, tracked in #12 // want: allocators/R1
package pure

quint :: proc(x: int) -> int {
	return x * 5
}
