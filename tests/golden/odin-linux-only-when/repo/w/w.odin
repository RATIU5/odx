package w

import "core:sys/linux"

f :: proc() {
	when ODIN_OS == .Linux {
		unused := 1
		_ = linux.getpid()
	}
}
