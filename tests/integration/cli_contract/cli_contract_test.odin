package cli_contract

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

import "../../probe"

@(test)
test_cli_errors_are_structured_and_removed_commands_stay_removed :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	bin := os.get_env("ODX", context.allocator)
	if bin == "" {bin, _ = filepath.abs("build/odx")}
	root, err := os.make_directory_temp("", "odx-cli-*", context.allocator)
	if !testing.expect(t, err == nil) {return}
	defer os.remove_all(root)
	testing.expect(
		t,
		os.write_entire_file(filepath.join({root, "odx.json5"}) or_else "", `{version:1}`) == nil,
	)
	testing.expect(
		t,
		os.write_entire_file(filepath.join({root, "main.odin"}) or_else "", "package example\n") ==
		nil,
	)
	cases := [][]string {
		{"topics"},
		{"for"},
		{"explain"},
		{"guidance"},
		{"doctor"},
		{"hook"},
		{"init"},
		{"rule"},
		{"self-test"},
		{"check", "--unsupported"},
		{"check", "--fast=true"},
		{"check", "--max-violations", "-1"},
		{"check", "--ci"},
		{"check", "--exemplar", "errors"},
		{"check", "--since", "missing-ref"},
		{"check", "missing-source"},
		{"check", "/"},
		{"check", "--topic", "missing-topic"},
		{"check", "--topic="},
		{"check", "--root"},
		{"policy", "--fast"},
		{"policy", "--rule", "R1"},
		{"policy", "--write", "AGENTS.md", "--verify", "AGENTS.md"},
		{"baseline", "missing-action"},
		{"ignores", "unexpected-path"},
	}
	for args in cases {
		cmd := make([dynamic]string)
		append(&cmd, bin)
		append(&cmd, ..args)
		append(&cmd, "--json", "--root", root)
		state, out, errors, run_err := os.process_exec({command = cmd[:]}, context.allocator)
		name := fmt.tprintf("%v: %s %s", args, out, errors)
		testing.expect(t, run_err == nil && state.exit_code == 2, name)
		response: probe.Report
		parse_err := json.unmarshal(out, &response)
		testing.expect(
			t,
			parse_err == nil && response.schema == 2 && len(response.tool_errors) > 0,
			name,
		)
		testing.expect(t, len(errors) == 0, name)
	}
	for source in ([]string{"{malformed", "{version:99}"}) {
		testing.expect(
			t,
			os.write_entire_file(filepath.join({root, "odx.json5"}) or_else "", source) == nil,
		)
		state, out, errors, run_err := os.process_exec(
			{command = {bin, "check", "--root", root, "--json"}},
			context.allocator,
		)
		response: probe.Report
		parse_err := json.unmarshal(out, &response)
		testing.expect(t, run_err == nil && state.exit_code == 2 && len(errors) == 0)
		testing.expect(
			t,
			parse_err == nil && response.schema == 2 && len(response.tool_errors) > 0,
		)
	}
	testing.expect(
		t,
		os.write_entire_file(filepath.join({root, "odx.json5"}) or_else "", `{version:1}`) == nil,
	)
	testing.expect(
		t,
		os.write_entire_file(
			filepath.join({root, "main.odin"}) or_else "",
			"package example\n// odx-ignore dependencies/R2 reason: enough explanation\nbroken :: proc( {",
		) ==
		nil,
	)
	for machine in ([]bool{false, true}) {
		cmd := make([dynamic]string)
		append(&cmd, bin, "ignores", "--root", root)
		if machine {append(&cmd, "--json")}
		state, out, errors, run_err := os.process_exec({command = cmd[:]}, context.allocator)
		testing.expect(
			t,
			run_err == nil && state.exit_code == 2,
			"ignore inventory must fail when source cannot be parsed",
		)
		if machine {
			response: probe.Report
			parse_err := json.unmarshal(out, &response)
			testing.expect(
				t,
				parse_err == nil && response.schema == 2 && len(response.tool_errors) > 0,
			)
			testing.expect(t, len(errors) == 0)
		} else {
			testing.expect(
				t,
				len(out) == 0 && len(errors) > 0,
				"incomplete inventory is reported as an error, without a clean listing",
			)
		}
	}
}
