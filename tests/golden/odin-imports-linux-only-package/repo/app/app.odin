package app

import "../lo"

who :: proc() -> int {
	return lo.pid()
}
