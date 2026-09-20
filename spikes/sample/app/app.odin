package app

import "../lib"

// run uses lib.
@(require_results)
run :: proc() -> lib.Error {
	_, err := lib.open("x")
	return err
}

main :: proc() {
	_ = run()
}
