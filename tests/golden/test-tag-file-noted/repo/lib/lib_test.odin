package lib

import "core:testing"

@(test)
suffix_only :: proc(t: ^testing.T) {
	testing.expect(t, true)
}
