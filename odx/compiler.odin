package odx

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:strings"

// This release's supported Odin range as `odin version` texts. Support is dropped only in a major release.
@(rodata)
SUPPORTED_COMPILERS := [?]string{"dev-2026-09-nightly:a2fb372"}

// `running` is the running compiler's version text, and `pin` is odx.json's `odin`, absent without
// odx.json. A mismatch is reported alone, because support only matters for the compiler that will run.
check_compiler :: proc(
	errors: ^[dynamic]Error,
	running: string,
	pin: Maybe(string),
	allocator: runtime.Allocator,
) {
	if p, pinned := pin.?; pinned && p != running {
		message := fmt.aprintf(
			"%s pins odin %s, but the running compiler is %s",
			CONFIG_FILE,
			p,
			running,
			allocator = allocator,
		)
		append(errors, Error{.Compiler_Mismatch, message})
	} else if !slice.contains(SUPPORTED_COMPILERS[:], running) {
		message := fmt.aprintf(
			"odin %s is outside the range this release supports: %s",
			running,
			strings.join(SUPPORTED_COMPILERS[:], ", ", context.temp_allocator),
			allocator = allocator,
		)
		append(errors, Error{.Compiler_Unsupported, message})
	}
}
