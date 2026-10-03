package app

import "../third_party/dep"

hello :: proc() -> int {
	return dep.greet()
}
