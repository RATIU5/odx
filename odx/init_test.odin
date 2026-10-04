package odx

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
	text := render_config(report, "2026-10-03", context.temp_allocator)
	config, errors := parse_config(text, ".", context.temp_allocator)

	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, config.rule_set, RULE_SET)
	testing.expect_value(t, config.odin, report.odin)
	testing.expect_value(t, len(config.pending), 2)
	for entry, i in config.pending {
		testing.expect_value(t, entry.dir, pending[i])
		testing.expect_value(t, entry.reason, "odx init 2026-10-03")
	}
	testing.expect_value(t, len(config.vendored), 2)
	for dir, i in config.vendored {
		testing.expect_value(t, dir, vendored[i])
	}
}

@(test)
render_config_leaves_out_empty_lists :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	text := render_config(Init_Report{odin = "v"}, "2026-10-03", context.temp_allocator)
	testing.expect_value(t, text, "{\n\t\"version\": 1,\n\t\"odin\": \"v\"\n}\n")
}
