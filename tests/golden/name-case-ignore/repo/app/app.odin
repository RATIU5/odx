package app

foreign import libc "system:c"

// odx:ignore name-case the C library spells it this way
sdl_version_t :: struct {
	major: u8,
}

Sdl_event :: struct {}

foreign libc {
	// odx:ignore name-case the C library spells it this way
	SDL_Init :: proc() ---
	SDL_Quit :: proc() ---
}

// odx:ignore name-case generated lookup, renamed with the next generator run
lookup := [?]int{1, 2}
