package app

import "core:fmt"

import "base:runtime"

import "core:strings"

show :: proc() {
	fmt.println(runtime.args__, strings.to_upper("a"))
}
