package odx

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"

// The compiler this release supports, as its `odin version` text. Support is dropped only in a
// major release.
SUPPORTED_COMPILER :: "dev-2026-09-nightly:a2fb372"

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
	} else if running != SUPPORTED_COMPILER {
		message := fmt.aprintf(
			"odin %s is outside the range this release supports: %s",
			running,
			SUPPORTED_COMPILER,
			allocator = allocator,
		)
		append(errors, Error{.Compiler_Unsupported, message})
	}
}

// What `odin root` printed, without a trailing `/`, or a message saying why odx couldn't read it.
// The error only stops a run that has packages to check.
Odin_Root :: struct {
	path:  string,
	error: string,
}

read_odin_root :: proc(odin: string, allocator: runtime.Allocator) -> Odin_Root {
	probe := probe_odin(odin, "root", allocator)
	if probe.error != "" {
		return {error = probe.error}
	}
	text := strings.trim_space(probe.stdout)
	if probe.status != (Exited{0}) || text == "" {
		b := strings.builder_make(allocator)
		fmt.sbprintf(&b, "'%s root' failed: %s", odin, status_text(probe.status, allocator))
		write_stderr_tail(&b, probe.stderr)
		return {error = strings.to_string(b)}
	}
	return {path = strings.trim_right(text, "/")}
}

// How long `odin version` and `odin root` may each take.
ODIN_PROBE_TIMEOUT :: 10 * time.Second

// How `odin <subcommand>` ended. `error` says why odx has no answer from it, and is "" otherwise.
Odin_Probe :: struct {
	stdout: string,
	stderr: string,
	status: Child_Status,
	error:  string,
}

// Runs `odin <subcommand>` within `ODIN_PROBE_TIMEOUT`. A probe whose streams odx couldn't read has
// an `error`, so an empty `stdout` is always what the compiler wrote. Allocates with `allocator`.
probe_odin :: proc(odin, subcommand: string, allocator: runtime.Allocator) -> (probe: Odin_Probe) {
	limit := debug_timeout("ODX_PROBE_TIMEOUT_MS", ODIN_PROBE_TIMEOUT)
	end, _ := run_captured(
		{command = {odin, subcommand}},
		{.Stdout, .Stderr},
		limit,
		nil,
		allocator,
	)
	switch {
	case end.error != "":
		probe.error = fmt.aprintf("'%s %s' %s", odin, subcommand, end.error, allocator = allocator)
	case end.timed_out:
		b := strings.builder_make(allocator)
		fmt.sbprintf(&b, "'%s %s' ", odin, subcommand)
		write_timeout(&b, limit)
		probe.error = strings.to_string(b)
	case:
		probe.stdout, probe.stderr = end.captured[.Stdout], end.captured[.Stderr]
		probe.status = end.status
	}
	return
}
