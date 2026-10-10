#+test
package lib

import "core:testing"

@(test)
second :: proc(t: ^testing.T) {
	testing.expect(t, true)
}
