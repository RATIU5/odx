// Shared harness for the integration suites under tests/integration/*/.
// Each suite keeps its own fixtures and assertions; the process plumbing and the
// decoded shape of `odx --json` live here so there is one copy of both.
package probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Probe :: struct {
	t:                     ^testing.T,
	bin, odin, root, base: string,
	passed, failed:        int,
}

// The types below mirror the JSON contract emitted by odx/report.odin, which is the
// source of truth: keep them in step with it when the report changes shape. Fields
// marked `json:"-"` there are absent here; everything the suites assert on is present.

Violation :: struct {
	file, rule, check, subject, message, severity, ignore_syntax: string,
	line, col:                                                    int,
	ignorable, baselined:                                         bool,
}

Rule_Metadata :: struct {
	check, class, statement, why, fix_hint, instead_of: string,
	fires, silent, evidence, boundary:                  string,
}

Source_Coverage :: struct {
	package_dir: string,
	files:       []string,
}

Check_Coverage :: struct {
	package_dir, rule, status, reason: string,
	findings:                          int,
}

Coverage :: struct {
	selection, selection_reason:          string,
	source_scope, compiler_scope:         string,
	compiler:                             string,
	complete:                             bool,
	packages:                             []Source_Coverage,
	checks:                               []Check_Coverage,
}

Report :: struct {
	schema:      int,
	rules:       map[string]Rule_Metadata,
	coverage:    Coverage,
	violations:  []Violation,
	tool_errors: []string,
	summary:     struct {
		errors, warnings, ignored, files, omitted, baselined: int,
	},
}

expect :: proc(p: ^Probe, ok: bool, name: string, loc := #caller_location) {
	testing.expect(p.t, ok, name, loc = loc)
	if ok {p.passed += 1} else {p.failed += 1}
	fmt.printfln("%s %s", "PASS" if ok else "FAIL", name)
}

// write places contents at path as given; intermediate directories are created.
write :: proc(path, contents: string) {
	err := os.make_directory_all(filepath.dir(path))
	if err != nil && err != os.General_Error.Exist {panic(fmt.tprintf("%v", err))}
	if err = os.write_entire_file(path, contents); err != nil {panic(fmt.tprintf("%v", err))}
}

// source places contents at a path relative to the probe root.
source :: proc(p: ^Probe, path, contents: string) {
	write(fmt.tprintf("%s/%s", p.root, path), contents)
}

read :: proc(p: ^Probe, path: string) -> string {
	data, err := os.read_entire_file(fmt.tprintf("%s/%s", p.root, path), context.allocator)
	if err != nil {panic(fmt.tprintf("%s: %v", path, err))}
	return string(data)
}

// exec runs an arbitrary command line and returns stdout and stderr joined.
exec :: proc(p: ^Probe, name: string, code: int, cmd: []string, loc := #caller_location) -> string {
	state, out, errors, err := os.process_exec({command = cmd}, context.allocator)
	expect(p, err == nil && state.exit_code == code, name, loc)
	if err != nil || state.exit_code != code {fmt.printfln("%s\n%s", out, errors)}
	return strings.concatenate({string(out), string(errors)})
}

// run_cli invokes the odx binary with args plus `--root <root>`, optionally forcing
// the compiler the tool uses, and returns both streams separately.
run_cli :: proc(
	p: ^Probe,
	name: string,
	code: int,
	args: []string,
	compiler := "",
	loc := #caller_location,
) -> (
	out, errors: string,
) {
	cmd := make([dynamic]string)
	append(&cmd, p.bin)
	append(&cmd, ..args)
	append(&cmd, "--root", p.root)
	env: [dynamic]string
	if compiler != "" {
		inherited, env_err := os.environ(context.allocator)
		if env_err != nil {panic(fmt.tprintf("%v", env_err))}
		for entry in inherited {
			if !strings.has_prefix(entry, "ODX_ODIN=") {append(&env, entry)}
		}
		append(&env, fmt.tprintf("ODX_ODIN=%s", compiler))
	}
	state, stdout, stderr, err := os.process_exec(
		{command = cmd[:], env = env[:]},
		context.allocator,
	)
	expect(
		p,
		err == nil && state.exit_code == code,
		fmt.tprintf("%s: exit %d (got %d, %v)", name, code, state.exit_code, err),
		loc,
	)
	if err != nil ||
	   state.exit_code != code {fmt.printfln("stdout: %s\nstderr: %s", stdout, stderr)}
	return string(stdout), string(stderr)
}

// run is run_cli when only stdout matters.
run :: proc(
	p: ^Probe,
	name: string,
	code: int,
	args: []string,
	compiler := "",
	loc := #caller_location,
) -> string {
	out, _ := run_cli(p, name, code, args, compiler, loc)
	return out
}

// report is run plus the decode every JSON suite performs.
report :: proc(
	p: ^Probe,
	name: string,
	code: int,
	args: []string,
	compiler := "",
	loc := #caller_location,
) -> Report {
	out := run(p, name, code, args, compiler, loc)
	r: Report
	expect(p, json.unmarshal_string(out, &r) == nil, fmt.tprintf("%s report decodes", name), loc)
	return r
}
