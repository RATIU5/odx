#+feature dynamic-literals
package app

f :: proc() {
	defer _ = #branch_location
}
