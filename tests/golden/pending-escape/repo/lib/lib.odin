package lib

foreign import outside "../../liboutside.a"

@(default_calling_convention = "c")
foreign outside {
	outside_count :: proc() -> i32 ---
}
