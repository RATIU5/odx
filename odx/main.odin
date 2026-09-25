package odx

import "core:fmt"

main :: proc() {
	fmt.println(greeting())
}

greeting :: proc() -> string {
	return "odx: hello, world"
}
