package fx

S :: struct {
	// odx:ignore name-case first field EXPECT=5
	A: int,
	b: int,
}

f :: proc(
	// odx:ignore name-case first param EXPECT=11
	X: int,
	y: int,
) {
	arr := [?]int{
		// odx:ignore line-length first element EXPECT=16
		1,
		2,
	}
	_ = arr
	x := 1 +
		// odx:ignore line-length binary rhs EXPECT=22
		2
	_ = x
    nested := [][]int{
        // odx:ignore line-length an element that is itself a literal EXPECT=26-28
        {
            1,
        },
    }
    _ = nested
}
