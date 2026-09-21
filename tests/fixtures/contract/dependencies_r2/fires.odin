#+vet explicit-allocators
package dependencies_r2

import "core:os" // want: dependencies/R2

quit :: proc() {
	os.exit(1)
}
