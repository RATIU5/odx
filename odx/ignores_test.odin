package odx

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
binding_covers_the_lines_each_fixture_expects :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	for name in ([]string{"fx.odin", "fx2.odin", "fx3.odin"}) {
		path := fmt.aprintf("tests/fixtures/ignore-binding/%s", name)
		data, read_err := os.read_entire_file(path, context.allocator)
		if !testing.expectf(t, read_err == nil, "%s: %v", path, read_err) {
			continue
		}
		src := string(data)
		tree, parse_error := parse_source(src, context.allocator)
		if !testing.expectf(t, parse_error == nil, "%s doesn't parse: %v", path, parse_error) {
			continue
		}
		line_starts := make_line_starts(src, context.allocator)
		b := make_binder(src, line_starts, tree, context.allocator)
		checked := 0
		for start, i in line_starts {
			end := line_starts[i + 1] if i + 1 < len(line_starts) else len(src)
			line := src[start:end]
			marker := strings.index(line, "// odx:ignore")
			if marker < 0 {
				continue
			}
			expect_at := strings.index(line, "EXPECT=")
			if !testing.expectf(
				t,
				expect_at >= 0,
				"%s:%d: an ignore with no EXPECT=",
				path,
				i + 1,
			) {
				continue
			}
			want := strings.trim_space(line[expect_at + len("EXPECT="):])
			covers, bound := bind(b, start + marker, context.allocator, context.allocator)
			got := format_runs(covers) if bound else "none"
			testing.expectf(t, got == want, "%s:%d: covers %s, want %s", path, i + 1, got, want)
			checked += 1
		}
		testing.expectf(t, checked > 0, "%s has no EXPECT= ignores", path)
	}
}

@(private = "file")
format_runs :: proc(runs: []Line_Run) -> string {
	b := strings.builder_make()
	for run, i in runs {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		if run.first == run.last {
			fmt.sbprintf(&b, "%d", run.first)
		} else {
			fmt.sbprintf(&b, "%d-%d", run.first, run.last)
		}
	}
	return strings.to_string(b)
}
