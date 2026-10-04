package app

f :: proc(n: int) -> int {
	total := 0
	switch n {
	case 1:
		total += 1
		fallthrough
	case 2:
		total += 2
	}
	return total
}
