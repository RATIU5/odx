#+vet explicit-allocators
package core

import "core:strings"

// split_words returns the whitespace-separated words of s. Caller owns the slice:
// delete(words, allocator).
split_words :: proc(s: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	rest := s
	for {
		word, _, tail := strings.partition(rest, " ")
		if word != "" {append(&out, word)}
		if tail == "" {break}
		rest = tail
	}
	return out[:]
}
