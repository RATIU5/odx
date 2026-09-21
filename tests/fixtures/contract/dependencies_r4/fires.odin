#+vet explicit-allocators
package dependencies_r4

foreign import libc "system:c" // want: dependencies/R4

@(default_calling_convention = "c")
foreign libc { // want: dependencies/R4
	abs :: proc(x: i32) -> i32 ---
}

magnitude :: proc(x: i32) -> i32 {
	return abs(x)
}
