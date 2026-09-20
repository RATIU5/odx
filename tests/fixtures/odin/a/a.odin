package a

@(deprecated = "errors/R1: return an Error instead of a bool")
old :: proc() -> bool {
	return true
}

broken :: proc() -> int {
	return "not an int" // want: odin/error
}
