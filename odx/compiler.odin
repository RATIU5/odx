package odx

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

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
	probe := probe_odin(odin, "root", allocator)
	if probe.error != "" {
		return {failure = probe.error}
	}
	text := strings.trim_space(probe.stdout)
	if probe.exit_code != 0 || text == "" {
		failure := fmt.aprintf(
			"'%s root' failed: exit %d, %s",
			odin,
			probe.exit_code,
			strings.trim_space(probe.stderr),
			allocator = allocator,
		)
		return {failure = failure}
	}
	return {path = strings.trim_right(text, "/")}
}

// How long `odin version` and `odin root` may each take.
ODIN_PROBE_TIMEOUT :: 10 * time.Second

// How `odin <subcommand>` ended. `error` says why odx has no answer from it, and is "" otherwise.
Odin_Probe :: struct {
	stdout:    string,
	stderr:    string,
	exit_code: int,
	error:     string,
}

// Runs `odin <subcommand>` within `ODIN_PROBE_TIMEOUT`. Allocates with `allocator`.
probe_odin :: proc(odin, subcommand: string, allocator: runtime.Allocator) -> (probe: Odin_Probe) {
	limit := debug_timeout("ODX_PROBE_TIMEOUT_MS", ODIN_PROBE_TIMEOUT)
	timed_out, err := run_probe(&probe, {odin, subcommand}, limit, allocator)
	switch {
	case err != nil:
		probe.error = fmt.aprintf(
			"could not run '%s %s': %v",
			odin,
			subcommand,
			err,
			allocator = allocator,
		)
	case timed_out:
		b := strings.builder_make(allocator)
		fmt.sbprintf(&b, "'%s %s' ", odin, subcommand)
		write_timeout(&b, limit)
		probe.error = strings.to_string(b)
	}
	return
}

// The streams go to files, as the pool's do. Reading a pipe to its end would wait for every
// process that holds it, and a killed wrapper script leaves such a child behind.
@(private = "file")
run_probe :: proc(
	probe: ^Odin_Probe,
	command: []string,
	limit: time.Duration,
	allocator: runtime.Allocator,
) -> (
	timed_out: bool,
	err: os.Error,
) {
	dir := os.make_directory_temp("", "odx-probe-*", allocator) or_return
	defer os.remove_all(dir)
	paths: [Stream]string
	files: [Stream]^os.File
	defer for file in files {
		if file != nil {
			os.close(file)
		}
	}
	for name, stream in STREAM_NAMES {
		paths[stream] = fmt.aprintf("%s/%s", dir, name, allocator = allocator)
		files[stream] = os.create(paths[stream]) or_return
	}
	process := os.process_start(
		{command = command, stdout = files[.Stdout], stderr = files[.Stderr]},
	) or_return
	state: os.Process_State
	state, err, timed_out, _ = wait_child(process, limit)
	if err != nil || timed_out {
		return
	}
	probe.exit_code = state.exit_code
	stdout := os.read_entire_file(paths[.Stdout], allocator) or_return
	stderr := os.read_entire_file(paths[.Stderr], allocator) or_return
	probe.stdout, probe.stderr = string(stdout), string(stderr)
	return
}
