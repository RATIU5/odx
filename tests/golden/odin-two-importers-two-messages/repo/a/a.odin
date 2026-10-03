package a

import "../lib"

f :: proc() -> string {
	return lib.add_one("s")
}
