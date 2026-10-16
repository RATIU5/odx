package p

f :: proc() {
	_ = "é"; defer _ = #branch_location
}
