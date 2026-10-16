#+vet !unused
package app

f :: proc() {
	defer _ = #branch_location
}
