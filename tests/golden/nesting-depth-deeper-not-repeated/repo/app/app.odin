package app

f :: proc(n: int) -> int {
	total := 0
	if n > 1 {
		if n > 2 {
			if n > 3 {
				if n > 4 {
					if n > 5 {
						if n > 6 {
							if n > 7 {
								if n > 8 {
									total += 1
								}
							}
						}
					}
				}
			}
		}
	}
	return total
}
