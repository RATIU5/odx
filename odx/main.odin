package odx

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

main :: proc() {
	os.exit(run_on_work_stack(run))
}

// The stack of the thread that does odx's work. `core:odin/parser`, odx's walk and the printer each
// recurse once per level of nesting in a source file, and none has a limit. With this much, the
// compiler's own stack ends at less than half the depth odx's does, for every shape of nesting
// probed, so a file that ends odx has ended the compiler first. The pages are committed only when
// touched.
WORK_STACK_SIZE :: 1 << 30

// Runs `work` on a new thread with `WORK_STACK_SIZE` of stack and returns its result. It runs
// `work` on the calling thread when no such thread starts. `core:thread` can't do this: it sizes a
// stack from the soft `RLIMIT_STACK`, which can't pass the hard limit, 64 MB on macOS.
run_on_work_stack :: proc(work: proc() -> int) -> int {
	Call :: struct {
		work:   proc() -> int,
		result: int,
	}
	call := Call {
		work = work,
	}
	attributes: posix.pthread_attr_t
	if posix.pthread_attr_init(&attributes) != .NONE {
		return work()
	}
	defer posix.pthread_attr_destroy(&attributes)
	thread: posix.pthread_t
	started :=
		posix.pthread_attr_setstacksize(&attributes, WORK_STACK_SIZE) == .NONE &&
		posix.pthread_create(&thread, &attributes, proc "c" (arg: rawptr) -> rawptr {
				context = runtime.default_context()
				call := (^Call)(arg)
				call.result = call.work()
				return nil
			}, &call) == .NONE
	if !started {
		return work()
	}
	posix.pthread_join(thread)
	return call.result
}

run :: proc() -> int {
	result := Result {
		rule_set = RULE_SET,
	}
	cmd: Check_Command
	switch parsed in parse_args(os.args[1:], context.allocator) {
	case Error:
		append(&result.errors, parsed)
	case Init_Command:
		return run_init()
	case Format_Child_Command:
		return run_format(parsed)
	case Help_Command:
		return print(HELP)
	case Version_Command:
		return print(version_line(context.allocator))
	case Check_Command:
		cmd = parsed
		if check_repo(&result) != nil {
			return 2
		}
	}
	if write_result(os.to_writer(os.stdout), os.to_writer(os.stderr), result, cmd) != nil {
		return 2
	}
	return exit_code(result)
}

@(private = "file")
print :: proc(text: string) -> int {
	if _, err := os.write_string(os.stdout, text); err != nil {
		return 2
	}
	return 0
}

// What it allocates with `context.allocator` lives until the process exits, and the result's
// findings borrow from it.
@(private = "file", require_results)
check_repo :: proc(result: ^Result) -> (note_err: os.Error) {
	repo := locate_repo(result)
	if len(result.errors) > 0 {
		return
	}
	config, odin := load(repo, result)
	if len(result.errors) > 0 {
		return
	}
	if !repo.has_config {
		note := fmt.tprintf(
			"odx: no odx.json, so rule set %d, the running compiler and every package strict\n",
			RULE_SET,
		)
		_ = os.write_string(os.stderr, note) or_return
	}
	odin_root := read_odin_root(odin, context.allocator)
	packages := discover(repo.root, config, result, context.allocator)
	if len(result.errors) > 0 {
		return
	}
	check(odin, odin_root, repo.root, config, packages[:], result)
	if len(result.errors) > 0 {
		return
	}
	note_test_tagged(packages[:], result)
	note_muted(packages[:], result)
	stale := stale_pending(
		repo.root,
		config.pending[:],
		packages[:],
		result.findings[:],
		context.allocator,
	)
	append(&result.findings, ..stale)
	sort_and_dedupe_findings(&result.findings)
	return
}

check :: proc(
	odin: string,
	odin_root: Odin_Root,
	root: string,
	config: Config,
	packages: []Package,
	result: ^Result,
) {
	if len(packages) > 0 {
		if odin_root.error != "" {
			append(&result.errors, Error{.Compiler_Output, odin_root.error})
			return
		}
		check_paths(packages, root, odin_root.path, config.collections[:], context.allocator)
		budget: Child_Budget
		init_child_budget(&budget, worker_count())
		// The checks start first, because a compile error must not wait for a slot that a print
		// holds until its timeout. A check is short, so the prints wait little.
		checks := start_compile(
			odin,
			odin_root.path,
			root,
			config,
			packages,
			&budget,
			context.allocator,
		)
		format := start_format(root, packages, &budget, context.allocator)
		finish_compile(checks, packages, result, context.allocator)
		if len(result.errors) > 0 {
			abandon_format(format)
			return
		}
		finish_format(format, packages, result, context.allocator)
		if len(result.errors) > 0 {
			return
		}
		add_file_findings(packages, result)
		apply_ignores(packages, result)
	}
}

// Finds the repo root from the working directory, or adds the error that stops the run. Allocates
// the root with `context.allocator`.
locate_repo :: proc(result: ^Result) -> Repo {
	cwd, cwd_err := os.get_working_directory(context.allocator)
	if cwd_err != nil {
		append(
			&result.errors,
			Error{.Config_Invalid, fmt.aprintf("could not find the repo root: %v", cwd_err)},
		)
		return {}
	}
	return find_repo(cwd, context.allocator)
}

// Sets the result's compiler and rule set from `odin version` and the repo's odx.json, or adds the
// errors that stop the run. Without odx.json, the config is empty. `odin` is the compiler's path.
load :: proc(repo: Repo, result: ^Result) -> (config: Config, odin: string) {
	version: string
	error: Maybe(Error)
	odin, version, error = read_odin_version()
	if e, failed := error.?; failed {
		append(&result.errors, e)
		return
	}
	result.odin = version
	if !repo.has_config {
		check_compiler(&result.errors, version, nil, context.allocator)
		return
	}
	errors: [dynamic]Error
	config, errors = load_config(repo.root, context.allocator)
	if len(errors) > 0 {
		append(&result.errors, ..errors[:])
		return
	}
	result.rule_set = config.rule_set
	check_compiler(&result.errors, version, config.odin, context.allocator)
	return
}

// Returns the compiler's path and the text after `odin version `. Both are allocated with
// `context.allocator` and stay alive for the process, so callers free neither.
@(require_results)
read_odin_version :: proc() -> (odin: string, version: string, error: Maybe(Error)) {
	found: bool
	odin, found = find_on_path(os.get_env("PATH", context.temp_allocator), "odin")
	if !found {
		return "", "", Error{.Odin_Missing, "'odin' is not on PATH"}
	}
	probe := probe_odin(odin, "version", context.allocator)
	if probe.error != "" {
		return "", "", Error{.Compiler_Output, probe.error}
	}
	// The compiler names itself by its argv[0], which here is the full path.
	prefix := fmt.tprintf("%s version ", odin)
	text := strings.trim_right_space(probe.stdout)
	switch status in probe.status {
	case Signaled:
		message := fmt.aprintf("'%s version' died by signal %d", odin, status.signal)
		return "", "", Error{.Compiler_Output, message}
	case Exited:
		if status.code != 0 || !strings.has_prefix(text, prefix) {
			return "", "", Error {
				.Compiler_Output,
				fmt.aprintf("'%s version' exited %d with unexpected output", odin, status.code),
			}
		}
	}
	return odin, text[len(prefix):], nil
}

// Searches only the non-empty entries of `dirs`, which is `PATH`'s value, so a file named `name` in
// the working directory never runs. Allocates the returned path with `context.allocator`.
@(require_results)
find_on_path :: proc(dirs, name: string) -> (path: string, found: bool) {
	for dir in strings.split(dirs, ":", context.temp_allocator) {
		if dir == "" {
			continue
		}
		candidate := strings.concatenate({dir, "/", name})
		// `access` asks whether this user may execute it, as a shell does, and opens nothing.
		c_candidate := strings.clone_to_cstring(candidate, context.temp_allocator)
		if disk_kind(candidate) == .File && posix.access(c_candidate, {.X_OK}) == .OK {
			return candidate, true
		}
		delete(candidate)
	}
	return "", false
}
