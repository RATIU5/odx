package app

import "core:fmt"

import lib "../Lib"

TEXT :: #load("../Data/Sub/Hello.txt")
HASH :: #load_hash("../Data/Sub/Hello.txt", "crc32")

foreign import libc "system:c"

foreign libc {
	getpid :: proc() -> i32 ---
}

show :: proc() {
	files := #load_directory("../Data/Sub")
	fmt.println(lib.X, len(TEXT), HASH, len(files), getpid())
}
