package app

f :: proc(n: int) -> int {
	total := 0
	if n > 1 {
		if n > 2 {
			if n > 3 {
				if n > 4 {
					if n > 5 {
						if n > 6 {
							bump := proc(n: int) -> int {
								total := 0
								if n > 11 {
									if n > 12 {
										if n > 13 {
											if n > 14 {
												if n > 15 {
													if n > 16 {
														total += 1
													}
												}
											}
										}
									}
								}
								return total
							}
							total += bump(n)
						}
					}
				}
			}
		}
	}
	return total
}
