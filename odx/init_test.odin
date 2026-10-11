package odx

import "core:fmt"
import "core:os"
import "core:testing"

@(test)
render_config_round_trips_through_the_config_parser :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	pending := []string{"a", `we"ird\dir`}
	vendored := []string{"third_party", "x/vendor"}
	report := Init_Report {
		odin     = "dev-2026-09-nightly:a2fb372",
		pending  = pending,
		vendored = vendored,
	}
	text := render_config(report, context.temp_allocator)
	config, errors := parse_config(text, ".", context.temp_allocator)

	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, config.rule_set, RULE_SET)
	testing.expect_value(t, config.odin, report.odin)
	testing.expect_value(t, len(config.pending), 2)
	for entry, i in config.pending {
		testing.expect_value(t, entry.dir, pending[i])
		testing.expect_value(t, entry.reason, "odx init")
	}
	testing.expect_value(t, len(config.vendored), 2)
	for dir, i in config.vendored {
		testing.expect_value(t, dir, vendored[i])
	}
}

@(test)
render_config_leaves_out_empty_lists :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	text := render_config(Init_Report{odin = "v"}, context.temp_allocator)
	expected := fmt.tprintf("{{\n\t\"version\": %d,\n\t\"odin\": \"v\"\n}}\n", RULE_SET)
	testing.expect_value(t, text, expected)
}

@(private = "file")
read_text :: proc(t: ^testing.T, dir, name: string) -> (text: string, exists: bool) {
	data, err := os.read_entire_file(fmt.tprintf("%s/%s", dir, name), context.temp_allocator)
	if err == os.General_Error.Not_Exist {
		return "", false
	}
	testing.expectf(t, err == nil, "reading %s: %v", name, err)
	return string(data), true
}

@(private = "file")
destroy_errors :: proc(result: ^Result) {
	for e in result.errors {
		delete(e.message)
	}
	delete(result.errors)
}

@(test)
write_init_files_writes_odx_json_and_the_odinfmt_json_the_binary_holds :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "odx-init-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)

	result: Result
	defer destroy_errors(&result)
	write_init_files(dir, "{}\n", true, &result)

	testing.expect_value(t, len(result.errors), 0)
	config, _ := read_text(t, dir, CONFIG_FILE)
	testing.expect_value(t, config, "{}\n")
	odinfmt, _ := read_text(t, dir, ODINFMT_FILE)
	testing.expect_value(t, odinfmt, ODINFMT_JSON)
}

@(test)
write_init_files_leaves_nothing_when_the_second_file_can_not_be_created :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "odx-init-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)
	theirs := fmt.tprintf("%s/%s", dir, ODINFMT_FILE)
	testing.expect_value(t, os.write_entire_file(theirs, "{}\n"), nil)

	result: Result
	defer destroy_errors(&result)
	write_init_files(dir, "{}\n", true, &result)

	testing.expect_value(t, len(result.errors), 1)
	if len(result.errors) == 1 {
		testing.expect_value(t, result.errors[0].code, Error_Code.Init_Exists)
		testing.expect_value(
			t,
			result.errors[0].message,
			"odinfmt.json already exists, so odx init wrote nothing",
		)
	}
	_, config_exists := read_text(t, dir, CONFIG_FILE)
	testing.expect(t, !config_exists, "odx.json was left behind")
	odinfmt, _ := read_text(t, dir, ODINFMT_FILE)
	testing.expect_value(t, odinfmt, "{}\n")
}

@(test)
needs_odinfmt_is_false_for_the_same_bytes_and_an_error_for_others :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "odx-init-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)
	path := fmt.tprintf("%s/%s", dir, ODINFMT_FILE)

	missing: Result
	defer destroy_errors(&missing)
	testing.expect(t, needs_odinfmt(dir, &missing), "a missing file must be written")
	testing.expect_value(t, len(missing.errors), 0)

	testing.expect_value(t, os.write_entire_file(path, ODINFMT_JSON), nil)
	same: Result
	defer destroy_errors(&same)
	testing.expect(t, !needs_odinfmt(dir, &same), "the same bytes must be left alone")
	testing.expect_value(t, len(same.errors), 0)

	testing.expect_value(t, os.write_entire_file(path, "{}\n"), nil)
	differs: Result
	defer destroy_errors(&differs)
	testing.expect(t, !needs_odinfmt(dir, &differs), "another file must not be written over")
	testing.expect_value(t, len(differs.errors), 1)
	if len(differs.errors) == 1 {
		testing.expect_value(t, differs.errors[0].code, Error_Code.Init_Exists)
		testing.expect_value(t, differs.errors[0].message, INIT_ODINFMT_DIFFERS)
	}
}
