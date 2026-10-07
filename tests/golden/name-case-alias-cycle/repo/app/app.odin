package app

when ODIN_OS == .Windows {
	first :: second
} else {
	first :: int
}

when ODIN_OS == .Windows {
	second :: int
} else {
	second :: first
}

third :: first
