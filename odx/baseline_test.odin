package odx

import "core:os"
import "core:testing"

// A `--since` run once emptied a baseline (full was computed without it); the file format and
// the key must survive a round trip, and a narrowed run must never be "full".
@(test)
test_baseline_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	// ponytail: not $TMPDIR, which Linux runners leave unset (the path became /odx-baseline)
	dir, terr := os.make_directory_temp("", "odx-baseline-*", context.allocator)
	testing.expect(t, terr == nil)
	defer os.remove_all(dir)
	write_baseline(
		dir,
		{
			{"dependencies/R2", "core", "core:os", "legacy, tracked in #7", false},
			{"errors/R3", ".", "parse", "", false},
		},
	)
	es, exists := read_baseline(dir)
	testing.expect(t, exists)
	if testing.expect_value(t, len(es), 2) {
		testing.expect_value(t, es[0].rule, "dependencies/R2") // sorted
		testing.expect_value(t, es[0].subject, "core:os")
		testing.expect_value(t, es[0].reason, "legacy, tracked in #7")
		testing.expect_value(t, es[1].rule, "errors/R3")
	}
	rule, pkg, subject, ok := baseline_key(
		Violation{file = "core/core.odin", rule = "dependencies/R2", subject = "core:os"},
	)
	testing.expect(t, ok)
	testing.expect_value(t, rule, "dependencies/R2")
	testing.expect_value(t, pkg, "core")
	testing.expect_value(t, subject, "core:os")
	_, pkg2, _, _ := baseline_key(Violation{file = "root.odin", rule = "x/R1", subject = "s"})
	testing.expect_value(t, pkg2, ".")
	_, _, _, ok3 := baseline_key(Violation{file = "a.odin", rule = "x/R1"}) // no subject
	testing.expect(t, !ok3)
}
