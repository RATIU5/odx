package app

import "../lib"

// run uses lib.
run :: proc() -> lib.Error {
	_, err := lib.open("x")
	return err
}

main :: proc() {
	run()
}
