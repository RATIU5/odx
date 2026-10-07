package app

import "base:runtime"
import "core:fmt"
import "core:strings"

import "vendor:zlib"

import "libs:util"

import "../lib"

show :: proc() {
	fmt.println(runtime.args__, strings.to_upper("a"), zlib.VERSION, util.LIMIT, lib.LIMIT)
}
