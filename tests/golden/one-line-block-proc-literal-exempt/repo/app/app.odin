package app

import "core:slice"

sort :: proc(s: []int) {
	slice.sort_by(s, proc(a, b: int) -> bool {return a < b})
}

f :: proc() {return}
