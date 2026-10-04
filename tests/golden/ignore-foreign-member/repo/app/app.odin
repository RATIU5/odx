package app

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
	// odx:ignore line-length the comment quotes the man page
	getpid :: proc() -> i32 --- // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
	getppid :: proc() -> i32 --- // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
}
