package odx

import "core:slice"
import "core:testing"

@(test)
check_compiler_reports_a_mismatch_before_support :: proc(t: ^testing.T) {
	allocator := context.temp_allocator

	cases := []struct {
		running: string,
		pin:     Maybe(string),
		want:    []Error_Code,
	} {
		{PIN, PIN, {}},
		{PIN, nil, {}},
		{"dev-2020-01:x", nil, {.Compiler_Unsupported}},
		{"dev-2020-01:x", "dev-2020-01:x", {.Compiler_Unsupported}},
		{"dev-2020-01:x", PIN, {.Compiler_Mismatch}},
		{PIN, "dev-2020-01:x", {.Compiler_Mismatch}},
	}
	for c in cases {
		errors := make([dynamic]Error, allocator)
		check_compiler(&errors, c.running, c.pin, allocator)
		got := make([dynamic]Error_Code, allocator)
		for e in errors {
			append(&got, e.code)
		}
		testing.expectf(t, slice.equal(got[:], c.want), "%v: got %v, want %v", c, got, c.want)
	}
}
