package odx

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// This release's supported Odin range as `odin version` texts. Support is dropped only in a major
// release.
@(rodata)
SUPPORTED_COMPILERS := [?]string{"dev-2026-09-nightly:a2fb372"}

// `running` is the running compiler's version text, and `pin` is odx.json's `odin`, absent without
// odx.json. A mismatch is reported alone, because support only matters for the compiler that will
// run.
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

// What `odin root` printed, without a trailing `/`, or a message saying why odx couldn't read it.
// The failure only stops a run that has packages to check.
Odin_Root :: struct {
	path:    string,
	failure: string,
}

read_odin_root :: proc(odin: string, allocator: runtime.Allocator) -> Odin_Root {
	state, stdout, stderr, err := os.process_exec({command = {odin, "root"}}, allocator)
	text := strings.trim_space(string(stdout))
	if err != nil || !state.success || text == "" {
		failure := fmt.aprintf(
			"'%s root' failed: exit %d, %s",
			odin,
			state.exit_code,
			strings.trim_space(string(stderr)),
			allocator = allocator,
		)
		return {failure = failure}
	}
	return {path = strings.trim_right(text, "/")}
}
