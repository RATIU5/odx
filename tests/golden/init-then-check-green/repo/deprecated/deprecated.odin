package deprecated

@(deprecated = "use greet")
old_greet :: proc() -> int {
	return 1
}

greet :: proc() -> int {
	return old_greet()
}
