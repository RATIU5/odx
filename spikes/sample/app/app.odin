package app

import "../lib"

// run uses lib.
@(require_results)
run :: proc() -> lib.Error { 	// odx:ignore errors/R5 reason: spike sample shows propagation itself; not shipped code
	_, err := lib.open("x")
	return err
}

main :: proc() {
	_ = run()
}
