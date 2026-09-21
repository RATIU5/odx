package a

@(deprecated = "errors/R3: add @(require_results)")
old :: proc() -> bool {
	return true
}

broken :: proc() -> int {
	return "not an int" // want: odin/error
}
