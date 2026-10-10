#+test
package main

broken :: proc() {
	x: int = "nope"
	_ = x
	undefined_call()
}
