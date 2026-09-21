#+vet explicit-allocators
package dependencies_r3

count: int // want: dependencies/R3

bump :: proc() -> int {
	count += 1
	return count
}
