package odx

import "core:testing"

@(test)
test_glob :: proc(t: ^testing.T) {
	Case :: struct {
		pat, path: string,
		want:      bool,
	}
	cases := []Case {
		{"src/core/**", "src/core", true},
		{"src/core/**", "src/core/math", true},
		{"src/core/**", "src/corex", false},
		{"**/*.odin", "a/b/c.odin", true},
		{"**/*.odin", "c.odin", true},
		{"**/*.odin", "c.txt", false},
		{"src/*", "src/core", true},
		{"src/*", "src/core/math", false},
		{"vendor/**", "vendor", true},
		{"*_test", "glob_test", true},
		{"a/**/z", "a/z", true},
		{"a/**/z", "a/b/c/z", true},
		{"a/**/z", "a/b/c", false},
		// the root package is zero segments, not one empty one
		{"*", "", false},
		{"**", "", true},
		{"**/*.odin", "", false},
		{"src/*", "src/", false},
		{"src/core/", "src/core", false},
		{"a/*/z", "a/z", false},
		{"a/**/**/z", "a/z", true},
	}
	for c in cases {
		testing.expectf(
			t,
			glob_match(c.pat, c.path) == c.want,
			"glob_match(%q, %q) != %v",
			c.pat,
			c.path,
			c.want,
		)
	}
}
