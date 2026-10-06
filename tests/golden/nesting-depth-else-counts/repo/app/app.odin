package app

f :: proc(n: int) -> int {
	total := 0
	if n == 1 {
		total += 1
	} else {
		if n == 2 {
			total += 2
		} else {
			if n == 3 {
				total += 3
			} else {
				if n == 4 {
					total += 4
				} else {
					if n == 5 {
						total += 5
					} else {
						if n == 6 {
							total += 6
						} else {
							if n == 7 {
								total += 7
							}
						}
					}
				}
			}
		}
	}
	return total
}
