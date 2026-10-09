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
		_ = os.write_string(os.stderr, NO_CONFIG_NOTE) or_return
	}
	odin_root := read_odin_root(odin, context.allocator)
	resolver: Resolver
	init_repo_resolver(&resolver, odin_root, config, result.odin)
	packages := discover(repo.root, config, &resolver, result, context.allocator)
	if len(result.errors) > 0 {
		return
	}
	check(odin, odin_root, repo.root, config, packages[:], result)
	if len(result.errors) > 0 {
		return
	}
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

// The resolver borrows `config`'s collections and allocates with `context.allocator`. Without an
// Odin root, imports of its collections stay unresolved, and `check` reports the failure.
init_repo_resolver :: proc(r: ^Resolver, odin_root: Odin_Root, config: Config, compiler: string) {
	universe, _ := universe_for(compiler)
	resolver_init(r, odin_root.path, config.collections[:], universe, context.allocator)
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
		if odin_root.failure != "" {
			append(&result.errors, Error{.Compiler_Output, odin_root.failure})
			return
		}
		temp_dir, temp_err := os.make_directory_temp("", "odx-check-*", context.allocator)
		if temp_err != nil {
			message := fmt.aprintf(
				"could not make a temp dir for compiler output: %s",
				os.error_string(temp_err),
			)
			append(&result.errors, Error{.Compiler_Output, message})
			return
		}
		defer os.remove_all(temp_dir)
		budget: Child_Budget
		init_child_budget(&budget, worker_count())
		// The checks start first, because a compile error must not wait for a slot that a print
		// holds until its timeout. A check is short, so the prints wait little.
		checks := start_compile(
			odin,
			odin_root.path,
			root,
			temp_dir,
			config,
			packages,
			&budget,
			context.allocator,
		)
		format := start_format(root, temp_dir, packages, &budget, context.allocator)
		finish_compile(checks, packages, result, context.allocator)
		if len(result.errors) > 0 {
			abandon_format(format)
			return
		}
		finish_format(format, packages, result, context.allocator)
		if len(result.errors) > 0 {
			return
		}
		check_paths(packages, root, odin_root.path, config.collections[:], context.allocator)
		add_file_findings(packages, result)
		apply_ignores(packages, result)
		note_hidden(packages, result)
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
	failure: Maybe(Error)
	odin, version, failure = read_odin_version()
	if e, failed := failure.?; failed {
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

// Searches only `PATH`'s non-empty entries, so a file named `name` in the working directory never
// runs. Allocates the returned path with `context.allocator`.
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
