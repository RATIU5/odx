package app

// fallthrough in a comment is not a statement.
f :: proc(n: int) -> int {
	total := 0
	switch n {
	case 1, 2:
		total += 1
	}
	return total
}
