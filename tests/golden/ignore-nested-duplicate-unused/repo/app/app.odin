package app

import "core:fmt"

f :: proc() {
	// odx:ignore line-length the log line quotes a URL
	fmt.println(
		"a",
		// odx:ignore line-length a URL
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	)
}
