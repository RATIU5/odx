package odx

import "core:slice"
import "core:testing"

@(test)
test_tokenize :: proc(t: ^testing.T) {
	Case :: struct {
		in_:  string,
		want: []string,
	}
	cases := []Case {
		{"HTTPServer", {"http", "server", "httpserver"}},
		{"builder_init", {"builder", "init", "builder_init"}},
		{"allocated hopping errors processes", {"allocate", "hop", "error", "process"}},
		{"the class is Error", {"class", "error"}},
		{"the and of", {}},
	}
	for c in cases {
		got := tokenize(c.in_)
		testing.expectf(
			t,
			slice.equal(got, c.want),
			"tokenize(%q) = %v, want %v",
			c.in_,
			got,
			c.want,
		)
	}
}
