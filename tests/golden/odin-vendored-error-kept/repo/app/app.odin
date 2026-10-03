package app

import "../third_party/dep"

total :: proc() -> int {
	return dep.count()
}
