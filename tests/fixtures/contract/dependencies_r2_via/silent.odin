#+vet explicit-allocators
package dependencies_r2_via

import "../dependencies_r3"

// a pure package that reaches nothing denied
count_pure :: proc() -> int {
	return dependencies_r3.bump()
}
