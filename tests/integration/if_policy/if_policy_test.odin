package if_policy

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../../probe"

join :: proc(parts: []string) -> string {
	path, _ := filepath.join(parts, context.allocator)
	return path
}
replace :: proc(text, old, replacement: string) -> string {
	result, _ := strings.replace_all(text, old, replacement, context.allocator)
	return result
}

check :: proc(p: ^probe.Probe, code: int, strict := false) -> probe.Report {
	args := make([dynamic]string)
	append(&args, "check", "--json", "--topic", "compact")
	if strict {append(&args, "--strict")}
	out := probe.run(p, "compact policy check", code, args[:])
	r: probe.Report
	testing.expect_value(p.t, json.unmarshal_string(out, &r), json.Unmarshal_Error(nil))
	return r
}

@(test)
test_compact_if_project :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-if-policy-*", context.allocator)
	if !testing.expect(t, err == nil) {return}
	defer os.remove_all(root)
	bin, _ := filepath.abs("build/odx")
	p := probe.Probe {
		t    = t,
		bin  = bin,
		root = root,
	}
	rule_path := ".odx/topics/compact/R1.odx.md"
	files := []string {
		"odx.json5",
		"compact.odin",
		"compact_test.odin",
		".odx/topics/compact/topic.md",
		rule_path,
	}
	for file in files {
		contents, read_err := os.read_entire_file(
			join({"examples/policies/compact-if", file}),
			context.allocator,
		)
		if !testing.expect(t, read_err == nil) {return}
		probe.write(join({root, file}), string(contents))
	}
	odin := os.get_env("ODX_ODIN", context.allocator)
	if !testing.expect(
		t,
		filepath.is_abs(odin),
		"ODX_ODIN must identify the pinned compiler",
	) {return}
	state, out, errors, exec_err := os.process_exec(
		{command = {odin, "test", root, fmt.tprintf("-out:%s/example-test", root)}},
		context.allocator,
	)
	testing.expect(
		t,
		exec_err == nil && state.exit_code == 0,
		fmt.tprintf("whole example project passes native tests\n%s\n%s", out, errors),
	)

	r := check(&p, 0)
	testing.expect_value(t, len(r.violations), 3)
	testing.expect(t, strings.contains(r.rules["compact/R1"].fix_hint, "do STATEMENT"))
	for finding in r.violations {
		testing.expect_value(t, finding.rule, "compact/R1")
		testing.expect_value(t, finding.severity, "warning")
		testing.expect_value(t, finding.file, "compact.odin")
		testing.expect(t, finding.line > 0 && finding.col > 0)
		testing.expect(t, strings.contains(finding.message, "if CONDITION do STATEMENT"))
	}
	r = check(&p, 1, true)
	testing.expect_value(t, len(r.violations), 3)
	policy := probe.run(&p, "policy listing", 0, {"policy", "--topic", "compact", "--json"})
	testing.expect(
		t,
		strings.contains(policy, `"match": "if"`) || strings.contains(policy, `"match":"if"`),
	)

	rule_file := join({root, rule_path})
	rule_bytes, _ := os.read_entire_file(rule_file, context.allocator)
	rule_source := string(rule_bytes)
	probe.write(rule_file, replace(rule_source, `severity: "warning"`, `severity: "error"`))
	r = check(&p, 1)
	for finding in r.violations {testing.expect_value(t, finding.severity, "error")}
	probe.write(rule_file, rule_source)

	source_file := join({root, "compact.odin"})
	source_bytes, _ := os.read_entire_file(source_file, context.allocator)
	source_text := string(source_bytes)
	probe.write(
		source_file,
		replace(
			source_text,
			"\tif ready {return 1}\n",
			"\t// odx:ignore compact/R1 reason: Keep the braced form for this example\n\tif ready {return 1}\n",
		),
	)
	r = check(&p, 0)
	testing.expect_value(t, len(r.violations), 2)
	probe.write(source_file, source_text)

	probe.run(&p, "baseline add", 0, {"baseline", "add"})
	r = check(&p, 0, true)
	testing.expect_value(t, len(r.violations), 3)
	for finding in r.violations {testing.expect(t, finding.baselined)}
	unchanged, _ := os.read_entire_file(source_file, context.allocator)
	testing.expect_value(t, string(unchanged), source_text)
}
