package app

foreign import libc "system:c"

foreign libc {
	SDL_Init :: proc(Flags: u32) -> i32 ---
	SDL_Quit :: proc() ---
	getpid :: proc() -> i32 ---
	Errno: i32
	environ: [^]cstring
}
