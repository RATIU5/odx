package milestone_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"

Result :: struct {
	name:   string,
	exit:   int,
	stdout: string,
	stderr: string,
}

run :: proc(results: ^[dynamic]Result, name: string, args: ..string) {
	state, stdout, stderr, err := os.process_exec({command = args}, context.allocator)
	if err != nil {panic(fmt.tprintf("%s: %v", name, err))}
	append(results, Result{name, state.exit_code, string(stdout), string(stderr)})
}

write :: proc(path, text: string) {
	if err := os.make_directory_all(filepath.dir(path)); err != nil && err != os.General_Error.Exist {panic(fmt.tprintf("%v", err))}
	if err := os.write_entire_file(path, text); err != nil {panic(fmt.tprintf("%v", err))}
}

write_config :: proc(root: string, no_roles := false, disabled := false) {
	write(fmt.tprintf("%s/odx.json5", root), fmt.tprintf(`{{
	version: 1, roles: %s,
	odin: {{ flags: [], explicit_allocators: "off" }},
	disabled: %s,
}}`, `{}` if no_roles else `{domain: ["lib"]}`,
		`{"dependencies/R9": "Deliberately disabled for probe"}` if disabled else `{}`))
}

write_rule :: proc(root: string, no_roles := false) {
	write(fmt.tprintf("%s/.odx/topics/dependencies/R9.odx.md", root), fmt.tprintf(`---
id: "R9",
statement: "No mutable package declarations",
why: "Keep state in parameters",
instead_of: "Mutable globals",
evidence: "Milestone 0 probe",
cost: "AST scan",
severity: "warning",
check: {{ kind: "pattern", match: "decl", at: "package_scope", mutable: true, roles: %s }},
---
Probe rule.
`, `[]` if no_roles else `["domain"]`))
}

// Run from the repository root. Observations include known bugs, not CI expectations.
main :: proc() {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	odin := os.get_env("ODX_ODIN", context.allocator)
	if odin == "" {panic("set ODX_ODIN to the reference compiler's absolute path")}
	results: [dynamic]Result
	run(&results, "compiler", odin, "version")
	run(&results, "source_revision", "git", "rev-parse", "HEAD")
	bin, err := filepath.abs("build/odx")
	if err != nil {panic(fmt.tprintf("%v", err))}
	run(&results, "binary_sha256", "shasum", "-a", "256", bin)
	fixture := "tests/fixtures/contract"
	run(&results, "graph_full", bin, "check", "--root", fixture, "--ci", "--json", "--topic", "dependencies")
	run(&results, "graph_scoped", bin, "check", "--root", fixture, "--ci", "--json", "--topic", "dependencies", "dependencies_r2_via")
	run(&results, "self", bin, "check", "--ci", "--json")
	root, terr := os.make_directory_temp("", "odx-m0-*", context.allocator)
	if terr != nil {panic(fmt.tprintf("%v", terr))}
	defer os.remove_all(root)
	write_config(root)
	write(fmt.tprintf("%s/lib/lib.odin", root), "package lib\n\ncount: int\nlimit :: 3\n")
	run(&results, "example_compiles", odin, "check", fmt.tprintf("%s/lib", root), "-no-entry-point")
	write(fmt.tprintf("%s/.odx/topics/dependencies/topic.md", root), `---
name: "dependencies",
summary: "Probe policy",
applies_to: { roles: ["edge"] },
---
Project policy probe.
`)
	write_rule(root)
	run(&results, "warning", bin, "check", "--root", root, "--ci", "--json")
	run(&results, "strict_warning", bin, "check", "--root", root, "--ci", "--json", "--strict")
	run(&results, "override", bin, "explain", "dependencies", "--root", root, "--json")
	run(&results, "path_guidance", bin, "for", fmt.tprintf("%s/lib", root), "--root", root, "--emit-claude-md")
	run(&results, "all_guidance", bin, "for", "--root", root, "--emit-claude-md")
	write(fmt.tprintf("%s/CLAUDE.md", root), "Human instructions.\n\n## odx\nStale sentinel.\n")
	run(&results, "init_existing_guidance", bin, "init", "--root", root, "--hooks")
	data, rerr := os.read_entire_file(fmt.tprintf("%s/CLAUDE.md", root), context.allocator)
	if rerr != nil {panic(fmt.tprintf("%v", rerr))}
	append(&results, Result{name = "existing_guidance_after_init", stdout = string(data)})
	write_config(root, disabled = true)
	run(&results, "disabled", bin, "check", "--root", root, "--ci", "--json", "--strict")
	run(&results, "disabled_guidance", bin, "for", "--root", root, "--emit-claude-md")
	write_config(root, no_roles = true)
	write_rule(root, no_roles = true)
	run(&results, "no_role_custom_rule", bin, "check", "--root", root, "--ci", "--json")
	write(fmt.tprintf("%s/lib/lib.odin", root), "package lib\n\nlimit :: 3\n")
	run(&results, "constant_counterexample", bin, "check", "--root", root, "--ci", "--json", "--strict")
	output, jerr := json.marshal(results[:], {pretty = true})
	if jerr != nil {panic(fmt.tprintf("%v", jerr))}
	fmt.println(string(output))
}
