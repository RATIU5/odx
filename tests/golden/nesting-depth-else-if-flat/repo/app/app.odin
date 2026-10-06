package app

f :: proc(n: int) -> int {
	total := 0
	if n > 1 {
		if n > 2 {
			if n > 3 {
				if n > 4 {
					if n > 5 {
						if n == 10 {
							total += 1
						} else if n == 11 {
							total += 2
						} else if n == 12 {
							total += 3
						} else if n == 13 {
							total += 4
						} else {
							total += 5
						}
					}
				}
			}
		}
	}
	return total
}
