package platform

import "core:fmt"
import "../core"

@(deprecated = "dependencies/R2: use core.parse instead of raw_parse")
raw_parse :: proc(s: string) -> int {
	return len(s)
}

main :: proc() {
	n, err := core.parse("abc")
	fmt.println(n, err, raw_parse("x")) // want: dependencies/R2
}
