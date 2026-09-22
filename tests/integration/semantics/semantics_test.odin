package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Probe :: struct {
	bin, root:      string,
	t: ^testing.T,
}

Report :: struct {
	coverage:   struct {
		complete: bool,
	},
	violations: []struct {
		rule, message: string,
	},
}

write :: proc(path, contents: string) {
	err := os.make_directory_all(filepath.dir(path))
	if err != nil && err != os.General_Error.Exist {panic(fmt.tprintf("%v", err))}
	if err = os.write_entire_file(path, contents); err != nil {panic(fmt.tprintf("%v", err))}
}
source :: proc(p: ^Probe, path, contents: string) {
	write(fmt.tprintf("%s/%s", p.root, path), contents)
}
expect :: proc(p: ^Probe, ok: bool, name: string) {
	testing.expect(p.t, ok, name)
}
run :: proc(p: ^Probe, name: string, code: int, args: []string) -> string {
	cmd := make([dynamic]string)
	append(&cmd, p.bin)
	append(&cmd, ..args)
	append(&cmd, "--root", p.root)
	state, out, errors, err := os.process_exec({command = cmd[:]}, context.allocator)
	expect(
		p,
		err == nil && state.exit_code == code,
		fmt.tprintf("%s: exit %d (got %d)", name, code, state.exit_code),
	)
	if err != nil || state.exit_code != code {fmt.printfln("%s\n%s", out, errors)}
	return string(out)
}
configure :: proc(p: ^Probe, errors: string) {
	source(
		p,
		"odx.json5",
		strings.concatenate(
			{`{version:1,odin:{explicit_allocators:"off",flags:[]},errors:`, errors, `}`},
		),
	)
}
check :: proc(p: ^Probe, name: string, expected: []string) {
	output := run(
		p,
		name,
		1 if len(expected) > 0 else 0,
		{"check", "--json", "--topic", "errors"},
	)
	report: Report
	expect(p, json.unmarshal_string(output, &report) == nil, "report decodes")
	expect(p, report.coverage.complete, "compiler evidence complete")
	expect(p, len(report.violations) == len(expected), fmt.tprintf("%s finding count", name))
	for symbol in expected {
		found := false
		for v in report.violations {
			if v.rule == "errors/R3" &&
			   strings.has_prefix(v.message, fmt.tprintf("%s returns ", symbol)) {found = true}
		}
		expect(p, found, fmt.tprintf("%s %s", name, symbol))
	}
}
MATRIX :: `package sample
Error :: enum {None, Bad}
Alias :: Error
Distinct :: distinct Error
Status :: enum {Ok, Pending}
Maybe :: union {int, string}
Nonoptional :: union #no_nil {int, string}
Read_Error :: enum {Done, Bad}
Write_Error :: enum {Done, Bad}
State :: enum {Ready, Busy}
AliasError :: State
predicate :: proc() -> bool {return false}
lookup :: proc(m: map[int]int, k: int) -> (int, bool) {v, ok := m[k]; return v, ok}
err :: proc() -> Error {return .Bad}
alias :: proc() -> Alias {return .Bad}
distinct_result :: proc() -> Distinct {return .Bad}
status :: proc() -> Status {return .Pending}
maybe :: proc() -> Maybe {return nil}
nonoptional :: proc() -> Nonoptional {return 1}
read :: proc() -> Read_Error {return .Bad}
write :: proc() -> Write_Error {return .Bad}
alias_spelling :: proc() -> AliasError {return .Busy}
anonymous :: proc() -> union {int, string} {return nil}
nonfinal :: proc() -> (Error, int) {return .Bad, 0}
@(private)
private_result :: proc() -> Error {return .Bad}
@(private="file")
file_private_result :: proc() -> Error {return .Bad}
@(require_results)
protected_result :: proc() -> Error {return .Bad}
`
@(test)
test_semantics :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	base, err := os.make_directory_temp("", "odx-semantics-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(base)
	bin, _ := filepath.abs("build/odx")
	p := Probe {
		t = t,
		bin  = bin,
		root = base,
	}
	source(&p, "sample/main.odin", MATRIX)
	source(
		&p,
		"sample/private.odin",
		"#+private\npackage sample\nfile_hidden :: proc() -> Error {return .Bad}\n",
	)
	source(
		&p,
		"sample/example_test.odin",
		`package sample
import "core:testing"
@(test)
error_test :: proc(_: ^testing.T) -> Error {return .Bad}
`,
	)
	configure(&p, `{}`)
	check(
		&p,
		"compatible default",
		{"err", "alias", "distinct_result", "status", "maybe", "read", "write"},
	)
	configure(&p, `{types:[]}`)
	check(&p, "structural only", {"err", "alias", "distinct_result", "status", "maybe"})
	configure(&p, `{structural:false}`)
	check(&p, "suffix only", {"err", "alias", "read", "write"})
	configure(&p, `{structural:false,types:["AliasError"]}`)
	check(&p, "alias spelling is not identity", {})
	configure(&p, `{structural:false,types:["Distinct"]}`)
	check(&p, "distinct name retained", {"distinct_result"})
	configure(&p, `{structural:false,types:[]}`)
	check(&p, "no classification", {})
	run(&p, "write guidance", 0, {"policy", "--write", "AGENTS.md"})
	configure(&p, `{structural:true,types:[]}`)
	run(&p, "structural change stales guidance", 1, {"policy", "--verify", "AGENTS.md"})
	run(&p, "regenerate guidance", 0, {"policy", "--write", "AGENTS.md"})
	run(&p, "fresh guidance", 0, {"policy", "--verify", "AGENTS.md"})
	for invalid in ([]string{`{structural:"false"}`, `{structural:0}`, `{structural:null}`, `{types:[""]}`, `{types:["  "]}`}) {
		configure(&p, invalid)
		run(&p, "invalid classification rejected", 2, {"check", "--fast"})
	}
	odin := os.get_env("ODX_ODIN", context.allocator)
	if odin == "" {odin = "odin"}
	for body, i in ([]string{"f()", "defer f()", "_ = f()", "_, _ = g()", "x, _ := g(); _ = x", "e := f(); _ = e"}) {
		path := fmt.tprintf("%s/compiler-%d.odin", base, i)
		write(
			path,
			strings.concatenate(
				{
					`package compiler_probe
Error :: enum {None, Bad}
@(require_results)
f :: proc() -> Error {return .Bad}
@(require_results)
g :: proc() -> (int, Error) {return 1, .Bad}
main :: proc() {`,
					body,
					"}\n",
				},
			),
		)
		state, out, errors, exec_err := os.process_exec(
			{command = {odin, "check", path, "-file", "-no-entry-point", "-vet", "-vet-cast"}},
			context.allocator,
		)
		want := 1 if i < 2 else 0
		expect(
			&p,
			exec_err == nil && state.exit_code == want,
			fmt.tprintf("compiler acknowledgement: %s", body),
		)
		if i <
		   2 {expect(&p, strings.contains(string(errors), "requires that its results must be handled"), "specific result acknowledgement diagnostic")}
		if state.exit_code != want {fmt.printfln("%s\n%s", out, errors)}
	}
	procedure_aliases(&p)
}
