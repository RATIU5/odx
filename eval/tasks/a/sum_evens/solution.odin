#+vet explicit-allocators
package task

sum_evens :: proc(xs: []int) -> int {
	total := 0
	for x in xs {if x % 2 == 0 {total += x}}
	return total
}
