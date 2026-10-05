package app

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
	call :: proc(first: i32, // the comment keeps the declaration on several lines
		vaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: i32,) -> i32 ---
}
