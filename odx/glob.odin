package odx

import "core:path/filepath"
import "core:strings"

// glob_match matches a `/`-separated path against a pattern (17.20):
// `**` = zero or more segments, `*` = one segment (may be partial: `*_test`),
// anything else = literal segment. filepath.match has no `**`, hence this.
glob_match :: proc(pattern, path: string) -> bool {
	pat := strings.split(pattern, "/", context.temp_allocator)
	segs := strings.split(path, "/", context.temp_allocator)
	return match_segs(pat, segs)
}

@(private = "file")
match_segs :: proc(pat, segs: []string) -> bool {
	if len(pat) == 0 {return len(segs) == 0}
	if pat[0] == "**" {
		for i in 0 ..= len(segs) {
			if match_segs(pat[1:], segs[i:]) {return true}
		}
		return false
	}
	if len(segs) == 0 {return false}
	ok, _ := filepath.match(pat[0], segs[0])
	return ok && match_segs(pat[1:], segs[1:])
}
