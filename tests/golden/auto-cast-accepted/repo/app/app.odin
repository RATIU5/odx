package app

// auto_cast in a comment is not a cast.
f :: proc(y: i64) -> i32 {
	x := i32(y)
	return x
}

NAME :: "auto_cast"
