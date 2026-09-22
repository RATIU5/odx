package compact

import "core:testing"

@(test)
test_conditionals :: proc(t: ^testing.T) {
	values := []bool{false, true}
	for ready in values {
		expected := 1 if ready else 0
		testing.expect_value(t, Braced_Return(ready), expected)
		testing.expect_value(t, Compact_Return(ready), expected)
		testing.expect_value(t, Braced_Assign(ready), expected)
		testing.expect_value(t, Compact_Assign(ready), expected)
		testing.expect_value(t, With_Else(ready), expected)
		testing.expect_value(t, Multiple_Statements(ready), expected * 2)
		braced, compact := 0, 0
		Braced_Call(ready, &braced)
		Compact_Call(ready, &compact)
		testing.expect_value(t, braced, expected)
		testing.expect_value(t, compact, expected)
	}
}
