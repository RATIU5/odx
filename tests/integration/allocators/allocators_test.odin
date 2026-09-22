package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Probe :: struct {
	bin, odin, root: string,
	t: ^testing.T,
}

Report :: struct {
	coverage:   struct {
		complete: bool,
	},
	violations: []struct {
		rule, message, boundary, fix_hint: string,
	},
}

write :: proc(path, contents: string) {
	err := os.make_directory_all(filepath.dir(path))
	if err != nil && err != os.General_Error.Exist {panic(fmt.tprintf("%v", err))}
	if err = os.write_entire_file(path, contents); err != nil {panic(fmt.tprintf("%v", err))}
}

expect :: proc(p: ^Probe, ok: bool, name: string) {
	testing.expect(p.t, ok, name)
}

run :: proc(p: ^Probe, name: string, code: int, cmd: []string) -> string {
	state, out, errors, err := os.process_exec({command = cmd}, context.allocator)
	expect(p, err == nil && state.exit_code == code, name)
	if err != nil || state.exit_code != code {fmt.printfln("%s\n%s", out, errors)}
	return strings.concatenate({string(out), string(errors)})
}

compiler_case :: proc(p: ^Probe, name, body: string, tagged, accepted: bool) {
	path := fmt.tprintf("%s/compiler/%s.odin", p.root, name)
	tag := "#+vet explicit-allocators\n" if tagged else ""
	write(path, strings.concatenate({tag, "package probe\n", body, "\n"}))
	out := run(
		p,
		name,
		0 if accepted else 1,
		{p.odin, "check", path, "-file", "-no-entry-point", "-vet"},
	)
	if !accepted {
		expect(
			p,
			strings.contains(out, "must be explicitly provided"),
			fmt.tprintf("%s fails for missing allocator", name),
		)
	}
}

policy_case :: proc(p: ^Probe, name, body: string, findings: int) {
	write(fmt.tprintf("%s/pure/main.odin", p.root), body)
	out := run(p, name, 1 if findings > 0 else 0, {p.bin, "check", "--root", p.root, "--json"})
	r: Report
	expect(p, json.unmarshal_string(out, &r) == nil, fmt.tprintf("%s JSON", name))
	expect(p, r.coverage.complete, fmt.tprintf("%s complete evidence", name))
	count := 0
	for v in r.violations {
		if v.rule != "allocators/R1" {continue}
		count += 1
		expect(
			p,
			strings.contains(v.message, "before the package declaration"),
			fmt.tprintf("%s directive position", name),
		)
		expect(
			p,
			strings.contains(v.boundary, "no allocator behavior or lifetime proof"),
			fmt.tprintf("%s limited guarantee", name),
		)
		expect(
			p,
			strings.contains(v.fix_hint, "allocator arguments required by the compiler"),
			fmt.tprintf("%s compiler repair guidance", name),
		)
	}
	expect(p, count == findings, fmt.tprintf("%s allocator findings", name))
}

@(test)
test_allocators :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-allocators-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(root)
	bin, _ := filepath.abs("build/odx")
	if override := os.get_env("ODX_BIN", context.allocator); override != "" {bin = override}
	odin := os.get_env("ODX_ODIN", context.allocator)
	if odin == "" {odin = "odin"}
	p := Probe {
		t = t,
		bin  = bin,
		odin = odin,
		root = root,
	}

	compiler_case(
		&p,
		"untagged_make",
		"f :: proc() { a := make([dynamic]int); delete(a) }",
		false,
		true,
	)
	compiler_case(
		&p,
		"tagged_make",
		"f :: proc() { a := make([dynamic]int); delete(a) }",
		true,
		false,
	)
	compiler_case(
		&p,
		"explicit_append",
		"f :: proc() { a := make([dynamic]int, context.allocator); append(&a, 1); delete(a) }",
		true,
		true,
	)
	compiler_case(
		&p,
		"zero_array_append",
		"f :: proc() { a: [dynamic]int; append(&a, 1); delete(a) }",
		true,
		true,
	)
	compiler_case(
		&p,
		"explicit_scratch",
		"f :: proc() { a := make([]int, 1, context.temp_allocator); _ = a }",
		true,
		true,
	)
	compiler_case(
		&p,
		"context_replacement",
		"f :: proc() { context.allocator = context.temp_allocator; a := make([dynamic]int); delete(a) }",
		true,
		false,
	)
	compiler_case(
		&p,
		"parameter_default",
		"f :: proc(allocator := context.allocator) { a := make([dynamic]int, allocator); delete(a) }",
		true,
		true,
	)
	compiler_case(
		&p,
		"omitted_parameter",
		"f :: proc(allocator := context.allocator) {}\ng :: proc() { f() }",
		true,
		false,
	)
	compiler_case(
		&p,
		"hidden_scratch",
		"import \"core:fmt\"\nf :: proc() { s := fmt.tprintf(\"%d\", 1); _ = s }",
		true,
		true,
	)

	write(
		fmt.tprintf("%s/odx.json5", root),
		`{version:1,roles:{pure:["pure"]},exclude:["compiler/**"],odin:{flags:[]}}`,
	)
	policy_case(
		&p,
		"scratch is not exempt",
		"package pure\nf :: proc() { a := make([]int, 1, context.temp_allocator); _ = a }\n",
		1,
	)
	policy_case(
		&p,
		"context replacement is not exempt",
		"package pure\nf :: proc() { context.allocator = context.temp_allocator }\n",
		1,
	)
	policy_case(
		&p,
		"reasoned file exemption",
		"// odx:ignore-file allocators/R1 reason: deliberate context interception boundary\npackage pure\nf :: proc() { context.allocator = context.temp_allocator }\n",
		0,
	)
	policy_case(
		&p,
		"header comment before directive",
		"// License header\n#+vet explicit-allocators\npackage pure\nf :: proc() {}\n",
		0,
	)
	policy_case(
		&p,
		"directive text in comment is not a tag",
		"// #+vet explicit-allocators\npackage pure\nf :: proc() {}\n",
		1,
	)
	write(
		fmt.tprintf("%s/odx.json5", root),
		`{version:1,roles:{pure:["pure"]},exclude:["compiler/**"],odin:{flags:[],explicit_allocators:"off"}}`,
	)
	policy_case(&p, "configured opt out", "package pure\nf :: proc() {}\n", 0)

}
