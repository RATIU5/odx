#+test
package lib

import "core:testing"

@(test)
first :: proc(t: ^testing.T) {
	testing.expect(t, true)
}
