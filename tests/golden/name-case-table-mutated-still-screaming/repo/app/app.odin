package app

NAMES := [?]string{"a", "b"}

ORDER := []int{3, 1, 2}

first :: proc() -> ^string {
	return &NAMES[0]
}

all :: proc() -> []string {
	return NAMES[:]
}

clear :: proc() {
	for &name in NAMES {
		name = ""
	}
}

order :: proc() -> []int {
	return ORDER
}
