package integration_probe

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

Violation :: struct {
	file, rule, subject, message: string,
}
Report :: struct {
	violations:  []Violation,
	tool_errors: []string,
	coverage:    struct {
		selection, source_scope: string,
		complete:                bool,
		packages:                []struct {
			package_dir: string,
		},
		checks:                  []struct {
			package_dir, rule, status: string,
		},
	},
}
Probe :: struct {
	bin, root, base: string,
	t:               ^testing.T,
}
CONFIG :: `{
 version: 1, roles: {pure: ["app"], service: ["dep"]},
 exclude: ["excluded/**", ".git/**"],
 dependencies: {pure: {may_import: ["service", "local:*", "core:*"], deny: ["core:os"]}},
 odin: {collections: {local: "."}, explicit_allocators: "off", flags: []},
}`

write :: proc(path, text: string) {
	err := os.make_directory_all(filepath.dir(path))
	if err != nil && err != os.General_Error.Exist {panic(fmt.tprintf("%v", err))}
	if err = os.write_entire_file(path, text); err != nil {panic(fmt.tprintf("%v", err))}
}
source :: proc(p: ^Probe, path, contents: string) {write(
		fmt.tprintf("%s/%s", p.root, path),
		contents,
	)}
expect :: proc(p: ^Probe, ok: bool, name: string) {
	testing.expect(p.t, ok, name)
}
setup :: proc(p: ^Probe, name: string) {
	p.root = fmt.aprintf("%s/%s", p.base, name)
	source(p, "odx.json5", CONFIG)
	source(p, "app/app.odin", "package app\nimport \"local:dep\"\n")
	source(p, "dep/dep.odin", "package dep\nvalue :: 42\n")
}
command :: proc(args: ..string) {
	state, out, errors, err := os.process_exec({command = args}, context.allocator)
	if err != nil ||
	   state.exit_code != 0 {panic(fmt.tprintf("%v: %v\n%s\n%s", args, err, out, errors))}
}
run :: proc(p: ^Probe, name: string, code: int, args: []string = nil) -> Report {
	cmd := make([dynamic]string)
	append(&cmd, p.bin, "check", "--root", p.root, "--fast", "--topic", "dependencies", "--json")
	append(&cmd, ..args)
	state, out, errors, err := os.process_exec({command = cmd[:]}, context.allocator)
	expect(
		p,
		err == nil && state.exit_code == code,
		fmt.tprintf("%s: exit %d (got %d)", name, code, state.exit_code),
	)
	if err != nil || state.exit_code != code {fmt.printfln("%s\n%s", out, errors)}
	r: Report
	jerr := json.unmarshal(out, &r)
	expect(p, jerr == nil && r.coverage.source_scope != "", fmt.tprintf("%s: coverage JSON", name))
	return r
}
findings :: proc(r: Report, pkg := "app/") -> string {
	out := make([dynamic]string)
	for v in r.violations {
		if v.rule == "dependencies/R2" && strings.has_prefix(v.file, pkg) {
			append(&out, fmt.tprintf("%s|%s|%s", v.file, v.subject, v.message))
		}
	}
	return strings.join(out[:], "\n")
}
architecture_complete :: proc(r: Report, pkg := "app") -> bool {
	for check in r.coverage.checks {
		if check.package_dir == pkg &&
		   check.rule == "dependencies/R2" {return check.status == "complete"}
	}
	return false
}
commit :: proc(p: ^Probe) {
	command("git", "-C", p.root, "add", ".")
	command(
		"git",
		"-C",
		p.root,
		"-c",
		"user.name=odx probe",
		"-c",
		"user.email=probe@example.invalid",
		"-c",
		"commit.gpgsign=false",
		"commit",
		"-qm",
		"probe",
	)
}

@(test)
test_architecture :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	odin := os.get_env("ODX_ODIN", context.allocator)
	if odin == "" ||
	   !filepath.is_abs(odin) {panic("set ODX_ODIN to the reference compiler's absolute path")}
	bin, _ := filepath.abs("build/odx")
	base, err := os.make_directory_temp("", "odx-architecture-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	defer os.remove_all(base)
	p := Probe {
		t    = t,
		bin  = bin,
		base = base,
	}
	setup(&p, "scopes")
	source(&p, "dep/dep.odin", "package dep\nimport \"core:os\"\n")
	full := run(&p, "full transitive", 1)
	file := run(&p, "file transitive", 1, {"app/app.odin"})
	dir := run(&p, "directory transitive", 1, {"app"})
	expect(
		&p,
		findings(full) != "" &&
		findings(full) == findings(file) &&
		findings(file) == findings(dir),
		"full/file/directory findings identical",
	)
	expect(
		&p,
		architecture_complete(file) && len(file.coverage.packages) == 1,
		"file scope has complete architecture evidence and selected reporting",
	)
	repeat := run(&p, "deterministic repeat", 1, {"app"})
	expect(&p, findings(dir) == findings(repeat), "dependency witness deterministic")

	setup(&p, "unassigned")
	source(&p, "app/app.odin", "package app\nimport \"local:unassigned\"\n")
	source(&p, "unassigned/u.odin", "package unassigned\nimport \"core:os\"\n")
	r := run(&p, "unassigned collection dependency", 1, {"app"})
	expect(
		&p,
		findings(r) != "" && architecture_complete(r),
		"unassigned role does not terminate graph",
	)

	for target in ([]string{"excluded", "missing"}) {
		setup(&p, target)
		source(&p, "app/app.odin", fmt.tprintf("package app\nimport \"local:%s\"\n", target))
		if target ==
		   "excluded" {source(&p, "excluded/e.odin", "package excluded\nimport \"core:os\"\n")}
		r = run(&p, target, 2, {"app"})
		expect(
			&p,
			!architecture_complete(r) && len(r.tool_errors) > 0,
			fmt.tprintf("%s evidence unavailable", target),
		)
	}
	setup(&p, "unknown")
	unknown_config, _ := strings.replace_all(CONFIG, `"local:*"`, `"local:*", "unknown:*"`)
	source(&p, "odx.json5", unknown_config)
	source(&p, "app/app.odin", "package app\nimport \"unknown:thing\"\n")
	r = run(&p, "unknown collection", 2, {"app"})
	expect(&p, !architecture_complete(r), "unknown collection is not a clean leaf")

	when ODIN_OS != .Windows {
		setup(&p, "canonical")
		symlink_error := os.symlink("dep", fmt.tprintf("%s/alias", p.root))
		if symlink_error != nil {panic(fmt.tprintf("%v", symlink_error))}
		source(&p, "app/app.odin", "package app\nimport \"../alias\"\n")
		source(&p, "dep/dep.odin", "package dep\nimport \"core:os\"\n")
		r = run(&p, "canonical directory alias", 1, {"app"})
		expect(
			&p,
			strings.contains(findings(r), "reaches") && architecture_complete(r),
			"symlink resolves package role and reach",
		)
	}

	setup(&p, "tests")
	source(&p, "dep/dep_test.odin", "package dep\nimport \"core:os\"\n")
	r = run(&p, "dependency test imports", 0, {"app"})
	expect(
		&p,
		architecture_complete(r) && findings(r) == "",
		"dependency test edges excluded from production reach",
	)
	source(&p, "app/app_test.odin", "package app\nimport \"core:os\"\n")
	r = run(&p, "selected package test imports", 1, {"app"})
	expect(&p, findings(r) != "", "selected package test imports checked")

	setup(&p, "platform")
	platform := "windows" if ODIN_OS != .Windows else "linux"
	source(&p, fmt.tprintf("dep/inactive_%s.odin", platform), "package dep\nimport \"core:os\"\n")
	r = run(&p, "inactive platform source", 1, {"app"})
	expect(&p, findings(r) != "", "inactive platform edges retained")

	setup(&p, "malformed")
	source(&p, "unrelated/broken.odin", "package unrelated\nbroken :: proc(\n")
	r = run(&p, "unrelated malformed source", 0, {"app"})
	expect(&p, architecture_complete(r), "unrelated parse failure does not poison reachability")
	source(&p, "dep/dep.odin", "package dep\nbroken :: proc(\n")
	r = run(&p, "reached malformed source", 2, {"app"})
	expect(&p, !architecture_complete(r), "reached parse failure prevents compliance")

	setup(&p, "cycle")
	source(&p, "dep/dep.odin", "package dep\nimport \"local:app\"\nimport \"core:os\"\n")
	r = run(&p, "source cycle", 1, {"app"})
	expect(
		&p,
		findings(r) != "" && architecture_complete(r),
		"cycles terminate without dropping denied edge",
	)

	setup(&p, "diamond")
	source(&p, "dep/dep.odin", "package dep\nimport \"local:left\"\nimport \"local:right\"\n")
	source(&p, "left/left.odin", "package left\nimport \"local:bottom\"\n")
	source(&p, "right/right.odin", "package right\nimport \"local:bottom\"\n")
	source(&p, "bottom/bottom.odin", "package bottom\nimport \"core:os\"\n")
	r = run(&p, "diamond graph", 1, {"app"})
	first_witness := findings(r)
	r = run(&p, "diamond graph repeat", 1, {"app"})
	expect(
		&p,
		first_witness != "" && first_witness == findings(r),
		"diamond selects stable dependency witness",
	)

	setup(&p, "literal")
	source(&p, "dep/dep.odin", "package dep\nimport \"core:os\"\n")
	source(&p, "app/app.odin", "package app\nimport `local:dep`\n")
	r = run(&p, "raw import literal", 1, {"app"})
	expect(
		&p,
		architecture_complete(r) && strings.contains(findings(r), "reaches"),
		"raw import literal resolves",
	)
	source(&p, "app/app.odin", "package app\nimport \"local:\\x64ep\"\n")
	r = run(&p, "escaped import literal", 1, {"app"})
	expect(
		&p,
		architecture_complete(r) && strings.contains(findings(r), "reaches"),
		"escaped import literal resolves",
	)

	setup(&p, "builtin-paths")
	source(&p, "app/app.odin", "package app\nimport \"core:fmt/../os\"\n")
	r = run(&p, "normalized direct builtin path", 1, {"app"})
	expect(
		&p,
		strings.contains(findings(r), "core:fmt/../os") && architecture_complete(r),
		"normalized direct deny preserves written subject",
	)
	source(&p, "app/app.odin", "package app\nimport \"local:dep\"\n")
	source(&p, "dep/dep.odin", "package dep\nimport \"core:fmt/../os\"\n")
	r = run(&p, "normalized transitive builtin path", 1, {"app"})
	expect(
		&p,
		strings.contains(findings(r), "reaches") && architecture_complete(r),
		"normalized transitive deny enforced",
	)
	source(&p, "dep/dep.odin", "package dep\nimport \"core:../core/os\"\n")
	r = run(&p, "builtin collection escape", 2, {"app"})
	expect(&p, !architecture_complete(r), "builtin collection escape evidence unavailable")

	setup(&p, "shadowed-builtin")
	shadow_config, _ := strings.replace_all(CONFIG, `local: "."`, `local: ".", core: "."`)
	shadow_config, _ = strings.replace_all(
		shadow_config,
		`deny: ["core:os"]`,
		`deny: ["vendor:*"]`,
	)
	source(&p, "odx.json5", shadow_config)
	source(&p, "app/app.odin", "package app\nimport \"core:dep\"\n")
	source(&p, "dep/dep.odin", "package dep\nimport \"vendor:forbidden\"\n")
	r = run(&p, "configured builtin shadow", 1, {"app"})
	expect(
		&p,
		strings.contains(findings(r), "reaches") && architecture_complete(r),
		"configured collection takes precedence over builtin leaf",
	)

	setup(&p, "outside-collection")
	outside_config, _ := strings.replace_all(CONFIG, `local: "."`, `local: "../external"`)
	source(&p, "odx.json5", outside_config)
	write(fmt.tprintf("%s/external/dep/dep.odin", p.base), "package dep\nvalue :: 42\n")
	r = run(&p, "configured external collection", 2, {"app"})
	expect(&p, !architecture_complete(r), "configured external collection evidence unavailable")

	setup(&p, "conditional-import")
	source(&p, "dep/dep.odin", "package dep\nwhen false { import \"core:os\" }\n")
	r = run(&p, "nested conditional import source", 1, {"app"})
	expect(
		&p,
		strings.contains(findings(r), "reaches"),
		"source graph includes inactive nested imports",
	)

	setup(&p, "incremental")
	command("git", "-C", p.root, "init", "-q")
	commit(&p)
	r = run(&p, "unchanged incremental", 0, {"--since", "HEAD"})
	expect(
		&p,
		len(r.coverage.packages) == 0 && !r.coverage.complete,
		"empty incremental selection makes no project claim",
	)
	source(&p, "dep/dep.odin", "package dep\nimport \"core:os\"\n")
	r = run(&p, "changed dependency", 1, {"--since", "HEAD"})
	expect(
		&p,
		findings(r) != "" && len(r.coverage.packages) == 2,
		"changed dependency checks unchanged importer",
	)
	commit(&p)
	changed_config, _ := strings.replace_all(CONFIG, `deny: ["core:os"]`, `deny: []`)
	source(&p, "odx.json5", changed_config)
	r = run(&p, "config-only change", 0, {"--since", "HEAD"})
	expect(&p, len(r.coverage.packages) == 2, "config-only change scans project")
	source(&p, "odx.json5", CONFIG)
	source(&p, "dep/other.odin", "package dep\nvalue :: 42\n")
	commit(&p)
	if remove_err := os.remove(fmt.tprintf("%s/dep/dep.odin", p.root));
	   remove_err != nil {panic(fmt.tprintf("%v", remove_err))}
	r = run(&p, "deleted source", 0, {"--since", "HEAD"})
	expect(&p, len(r.coverage.packages) == 2, "deleted source scans surviving project")
	commit(&p)
	if rename_err := os.rename(
		fmt.tprintf("%s/dep/other.odin", p.root),
		fmt.tprintf("%s/dep/renamed.odin", p.root),
	); rename_err != nil {panic(fmt.tprintf("%v", rename_err))}
	r = run(&p, "renamed source", 0, {"--since", "HEAD"})
	expect(&p, len(r.coverage.packages) == 2, "renamed source scans project")
	commit(&p)
	source(&p, ".odx/topics/research-note.txt", "Project policy change discovery probe.\n")
	r = run(&p, "local policy-only change", 0, {"--since", "HEAD"})
	expect(&p, len(r.coverage.packages) == 2, "local policy-only change scans project")

	setup(&p, "performance")
	for i in 0 ..< 100 {source(&p, fmt.tprintf("pkg%03d/p.odin", i), fmt.tprintf("package pkg%03d\nvalue :: %d\n", i, i))}
	for scoped in ([]bool{false, true}) {
		start := time.tick_now()
		for _ in 0 ..< 3 {
			args: []string
			if scoped {args = {"app"}}
			r = run(&p, "performance sample", 0, args)
		}
		fmt.printfln(
			"TIMING 102 packages, %s, mean %v",
			"file scope" if scoped else "project scope",
			time.tick_since(start) / 3,
		)
	}
}
