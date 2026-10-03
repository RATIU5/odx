// Case layout: `repo/` is copied to a temp dir and used as the working directory, `args` holds
// whitespace-separated arguments, the optional `env` holds `KEY=VALUE` lines applied over the
// inherited environment, the optional `cwd` names the subdirectory of `repo/` to run in, and
// `expected` holds the output as `render` writes it. An `env` value expands `${NAME}` from the
// inherited environment, and `${ODX_TESTS}` is the absolute `tests` dir.
package golden_runner

import odx "../../odx"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

CASE_TIMEOUT :: 30 * time.Second

Outcome :: struct {
	stdout:    string,
	stderr:    string,
	exit_code: int,
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
	entries, read_err := os.read_directory_by_path(golden, -1, context.allocator)
	if read_err != nil {
		fmt.eprintfln("runner: %s: %v", golden, read_err)
		return 2
	}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})

	passed, failed := 0, 0
	for entry in entries {
		if entry.type != .Directory {
			continue
		}
		dir := entry.fullpath
		expected, expected_err := os.read_entire_file(
			fmt.tprintf("%s/expected", dir),
			context.allocator,
		)
		outcome, run_err := run_case(odx_bin, dir, tests_dir)
		if expected_err != nil || run_err != "" {
			failed += 1
			fmt.printfln("FAIL %s: %s", entry.name, run_err != "" ? run_err : "no expected file")
			continue
		}
		actual := render(outcome, odin_version)
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
	fmt.printfln("golden: %d passed, %d failed", passed, failed)
	if failed > 0 || passed == 0 {
		return 1
	}
	return 0
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

// Returns a non-empty reason when the case couldn't be run.
run_case :: proc(odx_bin, dir, tests_dir: string) -> (outcome: Outcome, failure: string) {
	ta := context.temp_allocator
	args_text, args_err := os.read_entire_file(fmt.tprintf("%s/args", dir), ta)
	if args_err != nil {
		return {}, "no args file"
	}
	command := make([dynamic]string, ta)
	append(&command, odx_bin)
	append(&command, ..strings.fields(string(args_text), ta))

	env, env_err := os.environ(ta)
	if env_err != nil {
		return {}, "could not read the environment"
	}
	if env_text, err := os.read_entire_file(fmt.tprintf("%s/env", dir), ta); err == nil {
		env = apply_env(env, string(env_text), tests_dir)
	}

	tmp, tmp_err := os.make_directory_temp("", "odx-golden-*", ta)
	if tmp_err != nil {
		return {}, fmt.tprintf("temp dir: %v", tmp_err)
	}
	defer os.remove_all(tmp)
	repo := fmt.tprintf("%s/repo", tmp)
	if err := copy_tree(repo, fmt.tprintf("%s/repo", dir)); err != nil {
		return {}, fmt.tprintf("copy repo: %v", err)
	}

	working_dir := repo
	if cwd_text, err := os.read_entire_file(fmt.tprintf("%s/cwd", dir), ta); err == nil {
		working_dir = fmt.tprintf("%s/%s", repo, strings.trim_space(string(cwd_text)))
	}

	out_path, err_path := fmt.tprintf("%s/stdout", tmp), fmt.tprintf("%s/stderr", tmp)
	out_file, out_err := os.create(out_path)
	if out_err != nil {
		return {}, fmt.tprintf("create %s: %v", out_path, out_err)
	}
	err_file, err_err := os.create(err_path)
	if err_err != nil {
		os.close(out_file)
		return {}, fmt.tprintf("create %s: %v", err_path, err_err)
	}
	process, start_err := os.process_start(
		{
			working_dir = working_dir,
			command = command[:],
			env = env,
			stdout = out_file,
			stderr = err_file,
		},
	)
	os.close(out_file)
	os.close(err_file)
	if start_err != nil {
		return {}, fmt.tprintf("start odx: %v", start_err)
	}
	state, wait_err := os.process_wait(process, CASE_TIMEOUT)
	if wait_err == os.General_Error.Timeout {
		_ = os.process_kill(process)
		state, _ = os.process_wait(process)
		outcome.timed_out = true
	} else if wait_err != nil {
		return {}, fmt.tprintf("wait for odx: %v", wait_err)
	}
	outcome.exit_code = state.exit_code

	stdout, _ := os.read_entire_file(out_path, ta)
	stderr, _ := os.read_entire_file(err_path, ta)
	outcome.stdout, outcome.stderr = string(stdout), string(stderr)
	return outcome, ""
}

// Recreates symlinks as symlinks, dangling ones included, where `os.copy_directory_all` follows them
// and fails on a dangling one.
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

render :: proc(outcome: Outcome, odin_version: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	write_stream(&b, "stdout", outcome.stdout, odin_version)
	write_stream(&b, "stderr", outcome.stderr, odin_version)
	if outcome.timed_out {
		fmt.sbprintf(&b, "--- timed out after %v\n", CASE_TIMEOUT)
	} else {
		fmt.sbprintf(&b, "--- exit %d\n", outcome.exit_code)
	}
	return strings.to_string(b)
}

write_stream :: proc(b: ^strings.Builder, name, raw, odin_version: string) {
	ta := context.temp_allocator
	text, _ := strings.replace_all(raw, odin_version, "<odin>", ta)
	text, _ = strings.replace_all(text, odx.RELEASE, "<release>", ta)
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
