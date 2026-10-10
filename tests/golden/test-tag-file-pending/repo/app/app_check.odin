#+test
package app

import "core:testing"

@(test)
checks :: proc(t: ^testing.T) {
	testing.expect(t, true)
}
