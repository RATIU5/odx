#+test
package old

broken :: proc() {
	x: int = "nope"
	_ = x
	undefined_call()
}
