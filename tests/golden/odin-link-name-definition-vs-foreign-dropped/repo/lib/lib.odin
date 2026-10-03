package lib

foreign import libc "system:c"

foreign libc {
	clock :: proc "c" () -> i64 ---
}

when ODIN_OS == .Darwin || ODIN_OS == .Linux {
	foreign libc {
		time :: proc "c" (t: rawptr) -> i64 ---
	}
}

system_clock :: clock
system_time :: time

@(export, link_name = "clock")
my_clock :: proc "c" () -> i64 {
	return 0
}

@(export, link_name = "time")
my_time :: proc "c" (t: rawptr) -> i64 {
	return 0
}
