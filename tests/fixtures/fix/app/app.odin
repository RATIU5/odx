package app

import "core:fmt"

// odx:ignore layering/R3 reason: own-line ignore; edge packages may hold globals // want: odx/stale-ignore
counter: int

main :: proc() {
	counter += 1 // odx:ignore layering/R4 reason: end-of-line ignore that suppresses nothing // want: odx/stale-ignore
	fmt.println(counter)
}
