package odx

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_baseline_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	dir, terr := os.make_directory_temp("", "odx-baseline-*", context.allocator)
	testing.expect(t, terr == nil)
	defer os.remove_all(dir)
	fingerprint := strings.repeat("a", 64)
	original := []Baseline_Entry {
		{
			rule = "x/R2",
			file = "b.odin",
			subject = "parse\t#\"",
			fingerprint = fingerprint,
			line = 2,
			col = 1,
			reason = "legacy #7\ntracked\tcarefully",
		},
		{
			rule = "x/R1",
			file = "a.odin",
			subject = "name",
			fingerprint = fingerprint,
			line = 1,
			col = 1,
		},
	}
	testing.expect_value(t, write_baseline(dir, original), "")
	es, exists, err := read_baseline(dir)
	testing.expect(t, exists && err == "")
	if testing.expect_value(t, len(es), 2) {
		testing.expect_value(t, es[0].file, "a.odin")
		testing.expect_value(t, es[1].subject, "parse\t#\"")
		testing.expect_value(t, es[1].reason, "legacy #7\ntracked\tcarefully")
	}
}

@(test)
test_baseline_invalid_documents :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	dir, terr := os.make_directory_temp("", "odx-baseline-invalid-*", context.allocator)
	testing.expect(t, terr == nil)
	defer os.remove_all(dir)
	for text in ([]string{"format_version: 1\nx/R1\t.\tname\n", `{"format_version":99,"entries":[]}`, `{"format_version":2.5,"entries":[]}`, `{"format_version":18446744073709551618,"entries":[]}`, `{"format_version":2,"entries":null}`, `{"format_version":2,"entries":[{}]}`, `{"format_version":2,"entries":[],"ignored":true}`, `{"format_version":2,"entries":[],"format_version":2}`, "{"}) {
		testing.expect(t, os.write_entire_file(join({dir, BASELINE_FILE}), text) == nil)
		_, exists, err := read_baseline(dir)
		testing.expect(t, exists && err != "", text)
		unchanged, _ := os.read_entire_file(join({dir, BASELINE_FILE}), context.allocator)
		testing.expect_value(t, string(unchanged), text)
	}
}
