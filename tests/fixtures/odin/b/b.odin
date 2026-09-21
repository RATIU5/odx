package b // want: odin/error

import "../a"

main :: proc() {
	_ = a.old() // want: errors/R3
}
