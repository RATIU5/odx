package app

import "../lib"

GREETING :: "This constant is long on purpose, so that this one line runs past the one hundred column limit."

total :: proc() -> int {
	return lib.count()
}
