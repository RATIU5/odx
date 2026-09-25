package odx

import "core:testing"

@(test)
test_greeting :: proc(t: ^testing.T) {
	testing.expect_value(t, greeting(), "odx: hello, world")
}
