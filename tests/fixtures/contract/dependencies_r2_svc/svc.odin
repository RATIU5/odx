#+vet explicit-allocators
package dependencies_r2_svc

import "core:os"

// a service package may import core:os directly
argc :: proc() -> int {
	return len(os.args)
}
