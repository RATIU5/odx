package lib

@(deprecated = "use greet")
old_greet :: proc() -> int {
	return 1
}

greet :: proc() -> int {
	spare := 2
	return old_greet()
}
