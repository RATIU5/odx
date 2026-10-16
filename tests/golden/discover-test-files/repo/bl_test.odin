#+test
package p

f :: proc() {
	defer _ = #branch_location
}
