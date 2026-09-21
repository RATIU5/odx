#+vet explicit-allocators
package dependencies_r2_via

import "../dependencies_r2_svc" // want: dependencies/R2

// pure may import service, but through it this package reaches core:os
count :: proc() -> int {
	return dependencies_r2_svc.argc()
}
