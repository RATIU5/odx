package odx

import "core:testing"

@(test)
stale_pending_flags_entries_with_no_package_or_no_owned_findings :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	entries := []Pending_Entry {
		{"lib", "r", 2, 3},
		{"./clean/", "r", 3, 3},
		{"gone", "r", 4, 3},
		{"deep", "r", 5, 3},
		{"shown", "r", 6, 3},
		{"far", "r", 7, 3},
	}
	packages := []Package {
		{dir = "clean", status = .Pending},
		{dir = "deep", status = .Pending},
		{dir = "deep/inner", status = .Strict},
		{dir = "far", status = .Pending},
		{dir = "lib", status = .Pending},
		{dir = "shown", status = .Pending},
	}
	findings := []Finding {
		{
			path = "lib/a.odin",
			line = 1,
			col = 1,
			rule = .Line_Length,
			held_back = true,
			owner_dir = "lib",
		},
		{path = "deep/inner/b.odin", line = 1, col = 1, rule = .Odin, owner_dir = "deep/inner"},
		{path = "shown/c.odin", line = 1, col = 1, rule = .Import_Escape, owner_dir = "shown"},
		{
			path = "/elsewhere/d.odin",
			line = 1,
			col = 1,
			rule = .Odin,
			held_back = true,
			owner_dir = "far",
		},
	}

	stale := stale_pending("/repo", entries, packages, findings, context.temp_allocator)

	want := []struct {
		line: int,
		col:  int,
	}{{3, 3}, {4, 3}, {5, 3}}
	testing.expect_value(t, len(stale), len(want))
	for w, i in want {
		if i >= len(stale) {
			break
		}
		f := stale[i]
		testing.expectf(
			t,
			f.path == CONFIG_FILE &&
			f.rule == .Pending_Stale &&
			f.line == w.line &&
			f.col == w.col,
			"stale[%d] = %v, want %s:%d:%d",
			i,
			f,
			CONFIG_FILE,
			w.line,
			w.col,
		)
	}
}
