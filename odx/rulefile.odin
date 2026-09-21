package odx

import "core:strings"

// The frontmatter is the members of one JSON5 object, `key: value,` per line, and is handed to
// core:encoding/json unchanged: strings are quoted, there is no dialect. Fenced
// ```odin prelude|fires|silent blocks are exemplar, test and documentation at once.

Rule_File :: struct {
	frontmatter: string,
	prose:       string,
	prelude:     string,
	fires:       string,
	silent:      string,
}

parse_rule_file :: proc(text: string) -> (rf: Rule_File, err: string) {
	body := text
	if strings.has_prefix(text, "---\n") {
		rest := text[len("---\n"):]
		end := strings.index(rest, "\n---\n")
		if end < 0 {
			if strings.has_suffix(
				rest,
				"\n---",
			) {end = len(rest) - len("\n---")} else {return rf, "frontmatter is not closed by a `---` line"}
		}
		rf.frontmatter = strings.concatenate({"{\n", rest[:end], "\n}"})
		body = rest[min(end + len("\n---\n"), len(rest)):]
	} else {
		rf.frontmatter = "{}"
	}
	prose := strings.builder_make()
	lines := strings.split_lines(body, context.temp_allocator)
	i := 0
	for i < len(lines) {
		l := lines[i]
		if strings.has_prefix(l, "```odin ") || l == "```odin" {
			kind := strings.trim_space(strings.trim_prefix(l, "```odin"))
			j := i + 1
			for j < len(lines) && lines[j] != "```" {j += 1}
			if j >= len(lines) {return rf, "unterminated fenced block"}
			block := strings.join(lines[i + 1:j], "\n", context.temp_allocator)
			switch kind {
			case "prelude":
				rf.prelude = strings.clone(block)
			case "fires":
				rf.fires = strings.clone(block)
			case "silent":
				rf.silent = strings.clone(block)
			case "":
				strings.write_string(
					&prose,
					strings.join(lines[i:j + 1], "\n", context.temp_allocator),
				)
				strings.write_byte(&prose, '\n')
			case:
				return rf, strings.concatenate(
					{"unknown fenced block kind `", kind, "` (prelude, fires, silent)"},
				)
			}
			i = j + 1
			continue
		}
		strings.write_string(&prose, l)
		strings.write_byte(&prose, '\n')
		i += 1
	}
	rf.prose = strings.trim_space(strings.to_string(prose))
	return
}

// `#+` tags stay first, then the package clause: one prepended line, so a violation's line
// maps back as line-1.
block_source :: proc(block, pkg: string) -> string {
	tags, rest := strings.builder_make(), strings.builder_make()
	for l in strings.split_lines(block, context.temp_allocator) {
		if strings.has_prefix(l, "#+") && strings.builder_len(rest) == 0 {
			strings.write_string(&tags, l)
			strings.write_byte(&tags, '\n')
		} else {
			strings.write_string(&rest, l)
			strings.write_byte(&rest, '\n')
		}
	}
	return strings.concatenate(
		{strings.to_string(tags), "package ", pkg, "\n", strings.to_string(rest)},
	)
}
