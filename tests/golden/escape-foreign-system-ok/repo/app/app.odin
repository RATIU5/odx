package app

foreign import libc "system:c"

foreign libc {
	getpid :: proc() -> i32 ---
}
