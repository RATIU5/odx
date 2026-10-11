// Case layout: `repo/` is copied to a temp dir and used as the working directory, `args` holds one
// command per line as whitespace-separated arguments, run in order on the same copy, the optional
// `env` holds `KEY=VALUE` lines applied over the inherited environment, the optional `cwd` names
// the subdirectory of `repo/` to run in, the optional `readonly` file makes the copy's root
// directory read-only while the commands run, the optional `unreadable` file names one
// `repo/`-relative directory per line whose permissions are cleared while the commands run, and
// `expected` holds the output as `run_case` renders it. An `env` value expands `${NAME}` from the
// inherited environment, and `${ODX_TESTS}` is the absolute `tests` dir, which the rendering shows
// as `<tests>`. The rendering ends with `odx.json` and then `odinfmt.json`, each only when the
// commands created or changed it.
package runner

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

import "../../odx"

CASE_TIMEOUT :: 30 * time.Second

@(rodata)
WRITTEN_FILES := [?]string{odx.CONFIG_FILE, odx.ODINFMT_FILE}

// A file's text, or that there is none.
Snapshot :: struct {
	text:   string,
	exists: bool,
}

Placeholders :: struct {
	odin_version: string,
	tests_dir:    string,
}

Dir_Mode :: struct {
	path: string,
	mode: os.Permissions,
}

Outcome :: struct {
	stdout:    string,
	stderr:    string,
	status:    odx.Child_Status,
	timed_out: bool,
}

main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	if len(os.args) != 3 {
		fmt.eprintln("usage: runner <odx binary> <golden dir>")
		return 2
	}
	odx_bin, abs_err := os.get_absolute_path(os.args[1], context.allocator)
	if abs_err != nil {
		fmt.eprintfln("runner: %s: %v", os.args[1], abs_err)
		return 2
	}
	odin_version, version_ok := read_odin_version()
	if !version_ok {
		fmt.eprintln("runner: could not read 'odin version'")
		return 2
	}
	golden := os.args[2]
	golden_abs, golden_err := os.get_absolute_path(golden, context.allocator)
	if golden_err != nil {
		fmt.eprintfln("runner: %s: %v", golden, golden_err)
		return 2
	}
	tests_dir := os.dir(golden_abs)
	placeholders := Placeholders{odin_version, tests_dir}
	entries, read_err := os.read_directory_by_path(golden, -1, context.allocator)
	if read_err != nil {
		fmt.eprintfln("runner: %s: %v", golden, read_err)
		return 2
	}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})

	passed, failed, rerun := 0, 0, 0
	for entry in entries {
		if entry.type != .Directory {
			continue
		}
		dir := entry.fullpath
		expected, expected_err := os.read_entire_file(
			fmt.tprintf("%s/expected", dir),
			context.allocator,
		)
		actual, run_err := run_case(odx_bin, dir, tests_dir, placeholders)
		if expected_err == nil && run_err == "" && should_rerun(string(expected), actual) {
			rerun += 1
			fmt.printfln("RERUN %s (compiler signal)", entry.name)
			actual, run_err = run_case(odx_bin, dir, tests_dir, placeholders)
		}
		if expected_err != nil || run_err != "" {
			failed += 1
			fmt.printfln("FAIL %s: %s", entry.name, run_err != "" ? run_err : "no expected file")
			continue
		}
		if actual == string(expected) {
			passed += 1
			fmt.printfln("PASS %s", entry.name)
		} else {
			failed += 1
			fmt.printfln(
				"FAIL %s\n=== expected\n%s=== actual\n%s===",
				entry.name,
				string(expected),
				actual,
			)
		}
		free_all(context.temp_allocator)
	}
	fmt.printfln("golden: %d passed, %d failed, %d rerun", passed, failed, rerun)
	if failed > 0 || passed == 0 {
		return 1
	}
	return 0
}

// The pinned compiler sometimes dies by a signal under load. odx then runs it again and says so on
// stderr, or reports the second death. So the runner reruns a case once when its output has a line
// about a signal death that the case doesn't expect.
should_rerun :: proc(expected, actual: string) -> bool {
	return reports_compiler_signal(actual) && !reports_compiler_signal(expected)
}

reports_compiler_signal :: proc(rendered: string) -> bool {
	rest := rendered
	for line in strings.split_lines_iterator(&rest) {
		if strings.has_prefix(line, "odx: the compiler died by a signal ") ||
		   (strings.has_prefix(line, "odx: error: compiler-output: checking ") &&
				   strings.contains(line, " died by ")) {
			return true
		}
	}
	return false
}

// The runner reads the version itself, so a wrong version in odx's output never normalizes away.
read_odin_version :: proc() -> (version: string, ok: bool) {
	state, stdout, stderr, err := os.process_exec(
		{command = {"odin", "version"}},
		context.allocator,
	)
	delete(stderr)
	text := strings.trim_right_space(string(stdout))
	if err != nil || state.exit_code != 0 || !strings.has_prefix(text, "odin version ") {
		return "", false
	}
	return strings.trim_prefix(text, "odin version "), true
}

// Runs the case's commands in order on one copy of its repo and returns their rendered output, or a
// non-empty reason when the case couldn't be run.
run_case :: proc(
	odx_bin, dir, tests_dir: string,
	placeholders: Placeholders,
) -> (
	actual: string,
	failure: string,
) {
	ta := context.temp_allocator
	args_text, args_err := os.read_entire_file(fmt.tprintf("%s/args", dir), ta)
	if args_err != nil {
		return "", "no args file"
	}
	commands := make([dynamic]string, ta)
	for line in strings.split_lines(string(args_text), ta) {
		if strings.trim_space(line) != "" {
			append(&commands, line)
		}
	}

	env, env_err := os.environ(ta)
	if env_err != nil {
		return "", "could not read the environment"
	}
	if env_text, err := os.read_entire_file(fmt.tprintf("%s/env", dir), ta); err == nil {
		env = apply_env(env, string(env_text), tests_dir)
	}

	tmp, tmp_err := os.make_directory_temp("", "odx-golden-*", ta)
	if tmp_err != nil {
		return "", fmt.tprintf("temp dir: %v", tmp_err)
	}
	defer os.remove_all(tmp)
	repo := fmt.tprintf("%s/repo", tmp)
	if err := copy_tree(repo, fmt.tprintf("%s/repo", dir)); err != nil {
		return "", fmt.tprintf("copy repo: %v", err)
	}
	before: [len(WRITTEN_FILES)]Snapshot
	for name, i in WRITTEN_FILES {
		before[i] = snapshot(repo, name)
	}
	dir_modes := make([dynamic]Dir_Mode, ta)
	if os.exists(fmt.tprintf("%s/readonly", dir)) {
		append(&dir_modes, Dir_Mode{repo, os.Permissions_Read_All + os.Permissions_Execute_All})
	}
	if text, err := os.read_entire_file(fmt.tprintf("%s/unreadable", dir), ta); err == nil {
		for line in strings.split_lines(string(text), ta) {
			if sub := strings.trim_space(line); sub != "" {
				append(&dir_modes, Dir_Mode{fmt.tprintf("%s/%s", repo, sub), {}})
			}
		}
	}
	// remove_all can't empty a directory it can't write or list.
	defer for dm in dir_modes {
		if err := os.chmod(dm.path, os.Permissions_Default_Directory);
		   err != nil && failure == "" {
			actual, failure = "", fmt.tprintf("restore %s: %v", dm.path, err)
		}
	}
	for dm in dir_modes {
		if err := os.chmod(dm.path, dm.mode); err != nil {
			return "", fmt.tprintf("chmod %s: %v", dm.path, err)
		}
	}

	working_dir := repo
	if cwd_text, err := os.read_entire_file(fmt.tprintf("%s/cwd", dir), ta); err == nil {
		working_dir = fmt.tprintf("%s/%s", repo, strings.trim_space(string(cwd_text)))
	}

	b := strings.builder_make(ta)
	for line in commands {
		command := make([dynamic]string, ta)
		append(&command, odx_bin)
		append(&command, ..strings.fields(line, ta))
		outcome, run_err := run_command(command[:], working_dir, env)
		if run_err != "" {
			return "", run_err
		}
		if len(commands) > 1 {
			fmt.sbprintf(&b, "=== odx %s\n", strings.trim_space(line))
		}
		render(&b, outcome, placeholders)
	}
	for name, i in WRITTEN_FILES {
		if after := snapshot(repo, name); after.exists && after != before[i] {
			write_stream(&b, name, after.text, placeholders)
		}
	}
	return strings.to_string(b), ""
}

// Allocates the text with `context.temp_allocator`.
snapshot :: proc(repo, name: string) -> Snapshot {
	data, err := os.read_entire_file(fmt.tprintf("%s/%s", repo, name), context.temp_allocator)
	return {string(data), err == nil}
}

run_command :: proc(
	command: []string,
	working_dir: string,
	env: []string,
) -> (
	outcome: Outcome,
	failure: string,
) {
	end, _ := odx.run_captured(
		{working_dir = working_dir, command = command, env = env},
		{.Stdout, .Stderr},
		CASE_TIMEOUT,
		nil,
		context.temp_allocator,
	)
	if end.error != "" {
		return {}, fmt.tprintf("odx %s", end.error)
	}
	return {end.captured[.Stdout], end.captured[.Stderr], end.status, end.timed_out}, ""
}

// Recreates symlinks as symlinks, dangling ones included, where `os.copy_directory_all` follows
// them and fails on a dangling one.
copy_tree :: proc(dst, src: string) -> os.Error {
	ta := context.temp_allocator
	os.make_directory(dst) or_return
	entries := os.read_directory_by_path(src, -1, ta) or_return
	for entry in entries {
		to := fmt.tprintf("%s/%s", dst, entry.name)
		#partial switch entry.type {
		case .Directory:
			copy_tree(to, entry.fullpath) or_return
		case .Symlink:
			target := os.read_link(entry.fullpath, ta) or_return
			os.symlink(target, to) or_return
		case:
			os.copy_file(to, entry.fullpath) or_return
		}
	}
	return nil
}

apply_env :: proc(env: []string, text, tests_dir: string) -> []string {
	ta := context.temp_allocator
	result := slice.clone_to_dynamic(env, ta)
	for raw in strings.split_lines(text, ta) {
		if raw == "" {
			continue
		}
		key := raw[:max(strings.index_byte(raw, '='), 0)]
		line := strings.concatenate({key, "=", expand(raw[len(key) + 1:], env, tests_dir)}, ta)
		replaced := false
		for &existing in result {
			if strings.has_prefix(existing, key) &&
			   len(existing) > len(key) &&
			   existing[len(key)] == '=' {
				existing = line
				replaced = true
			}
		}
		if !replaced {
			append(&result, line)
		}
	}
	return result[:]
}

render :: proc(b: ^strings.Builder, outcome: Outcome, placeholders: Placeholders) {
	write_stream(b, "stdout", outcome.stdout, placeholders)
	write_stream(b, "stderr", outcome.stderr, placeholders)
	switch status in outcome.status {
	case odx.Signaled:
		if outcome.timed_out {
			fmt.sbprintf(b, "--- timed out after %v\n", CASE_TIMEOUT)
		} else {
			fmt.sbprintf(b, "--- signal %d\n", status.signal)
		}
	case odx.Exited:
		fmt.sbprintf(b, "--- exit %d\n", status.code)
	}
}

write_stream :: proc(b: ^strings.Builder, name, raw: string, placeholders: Placeholders) {
	ta := context.temp_allocator
	text, _ := strings.replace_all(raw, placeholders.odin_version, "<odin>", ta)
	text, _ = strings.replace_all(text, odx.RELEASE, "<release>", ta)
	text, _ = strings.replace_all(text, placeholders.tests_dir, "<tests>", ta)
	fmt.sbprintf(b, "--- %s\n%s", name, text)
	if text != "" && !strings.has_suffix(text, "\n") {
		strings.write_string(b, "\n\\ no newline at end\n")
	}
}

expand :: proc(value: string, env: []string, tests_dir: string) -> string {
	ta := context.temp_allocator
	b := strings.builder_make(ta)
	rest := value
	for {
		open := strings.index(rest, "${")
		close := strings.index_byte(rest[max(open, 0):], '}')
		if open < 0 || close < 0 {
			break
		}
		name := rest[open + 2:open + close]
		strings.write_string(&b, rest[:open])
		strings.write_string(&b, tests_dir if name == "ODX_TESTS" else lookup(env, name))
		rest = rest[open + close + 1:]
	}
	strings.write_string(&b, rest)
	return strings.to_string(b)
}

lookup :: proc(env: []string, name: string) -> string {
	for entry in env {
		if strings.has_prefix(entry, name) && len(entry) > len(name) && entry[len(name)] == '=' {
			return entry[len(name) + 1:]
		}
	}
	return ""
}
