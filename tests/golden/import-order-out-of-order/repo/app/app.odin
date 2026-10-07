package app

import "vendor:zlib"

import "core:fmt"

import "../lib"

import "base:runtime"

show :: proc() {
	fmt.println(runtime.args__, zlib.VERSION, lib.LIMIT)
}
