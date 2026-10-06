package app

f :: proc(n: int) -> int {
	total := 0
	if n > 1 {
		if n > 2 {
			if n > 3 {
				if n > 4 {
					switch n {
					case 10:
						if n > 5 {
							total += 1
						}
					case:
						total += 2
					}
				}
			}
		}
	}
	return total
}
