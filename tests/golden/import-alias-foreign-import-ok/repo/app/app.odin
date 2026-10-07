package app

foreign import c "system:c"

foreign c {
	getpid :: proc() -> i32 ---
}
