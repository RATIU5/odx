package odx

import "core:testing"

@(test)
escapes_decides_by_repo_and_odin_code :: proc(t: ^testing.T) {
	roots := Roots{"/w/repo", {"/o/base", "/o/core", "/o/vendor"}}
	cases := []struct {
		kind: Path_Kind,
		real: string,
		want: bool,
	} {
		{.Import, "/w/repo/lib", false},
		{.Import, "/w/repo", false},
		{.Import, "/w/repo2/lib", true},
		{.Import, "/w/outside", true},
		{.Import, "/o/core/fmt", false},
		{.Load, "/o/base/runtime/core.odin", false},
		{.Foreign_Import, "/o/vendor/raylib/lib.a", false},
		{.Import, "/o/shared/foo", true},
		{.Import, "/o/corex", true},
		{.Import, "/o", true},
		{.File_Symlink, "/o/core/fmt/fmt.odin", true},
		{.File_Symlink, "/w/repo/a/b.odin", false},
	}
	for c in cases {
		got := escapes(c.kind, c.real, roots)
		testing.expectf(t, got == c.want, "%v %q: got %v, want %v", c.kind, c.real, got, c.want)
	}
}
