package task

import "core:testing"

@(test)
test_sum_evens :: proc(t: ^testing.T) {
	testing.expect_value(t, sum_evens({}), 0)
	testing.expect_value(t, sum_evens({1, 2, 3, 4}), 6)
	testing.expect_value(t, sum_evens({-2, -3}), -2)
}
