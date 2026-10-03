package odx

import "core:fmt"
import "core:os"
import "core:strings"

NO_CONFIG_NOTE :: "odx: no odx.json, so rule set 1, the running compiler and every package strict\n"

main :: proc() {
	os.exit(run())
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
		append(&result.errors, Error{.Usage, "'odx init' is not built yet"})
	case Check_Command:
		cmd = parsed
	}

	if len(result.errors) == 0 {
		repo, config, odin := load(&result)
		if len(result.errors) == 0 {
			if !repo.has_config {
				os.write_string(os.stderr, NO_CONFIG_NOTE)
			}
			packages := discover(repo.root, config, &result, context.allocator)
			compile(odin, repo.root, config, packages[:], &result, context.allocator)
			sort_findings(&result.findings)
		}
	}
	if write_result(os.to_writer(os.stdout), os.to_writer(os.stderr), result, cmd) != nil {
		return 2
	}
	return exit_code(result)
}

// Sets the result's compiler and rule set from `odin version` and odx.json, or adds the errors that
// stop the run. Without odx.json, the config is empty. `odin` is the compiler's path.
load :: proc(result: ^Result) -> (repo: Repo, config: Config, odin: string) {
	version: string
	failure: Maybe(Error)
	odin, version, failure = read_odin_version()
	if e, failed := failure.?; failed {
		append(&result.errors, e)
		return
	}
	result.odin = version
	cwd, cwd_err := os.get_working_directory(context.allocator)
	if cwd_err != nil {
		append(
			&result.errors,
			Error{.Config_Invalid, fmt.aprintf("could not find the repo root: %v", cwd_err)},
		)
		return
	}
	repo = find_repo(cwd, context.allocator)
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

// Returns the compiler's path and the text after `odin version `. Both live in one
// `context.allocator` allocation that stays alive for the process, so callers free neither.
read_odin_version :: proc() -> (odin: string, version: string, failure: Maybe(Error)) {
	found: bool
	odin, found = find_on_path("odin")
	if !found {
		return "", "", Error{.Odin_Missing, "'odin' is not on PATH"}
	}
	state, stdout, stderr, err := os.process_exec({command = {odin, "version"}}, context.allocator)
	delete(stderr)
	if err != nil {
		delete(stdout)
		return "", "", Error {
			.Compiler_Output,
			fmt.aprintf("could not run '%s version': %v", odin, err),
		}
	}
	// The compiler names itself by its argv[0], which here is the full path.
	prefix := fmt.tprintf("%s version ", odin)
	text := strings.trim_right_space(string(stdout))
	if !state.success || state.exit_code != 0 || !strings.has_prefix(text, prefix) {
		delete(stdout)
		return "", "", Error {
			.Compiler_Output,
			fmt.aprintf("'%s version' exited %d with unexpected output", odin, state.exit_code),
		}
	}
	return odin, text[len(prefix):], nil
}

// Searches only `PATH`'s non-empty entries, so a file named `name` in the working directory never runs.
// Allocates the returned path with `context.allocator`.
find_on_path :: proc(name: string) -> (path: string, found: bool) {
	dirs := strings.split(os.get_env("PATH", context.temp_allocator), ":", context.temp_allocator)
	for dir in dirs {
		if dir == "" {
			continue
		}
		candidate := strings.concatenate({dir, "/", name})
		info, err := os.stat(candidate, context.temp_allocator)
		if err == nil && info.type == .Regular && info.mode & os.Permissions_Execute_All != {} {
			return candidate, true
		}
		delete(candidate)
	}
	return "", false
}
