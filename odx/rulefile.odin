package odx

import "core:strings"

// The .odx.md format (M8.2): one file per rule, and one topic.md per topic. Restricted
// frontmatter between `---` lines: `key: value`, where a value that starts with `{` or `[`, or is
// true/false or a number, is inline JSON5, and anything else is a string. The body is Markdown
// whose fenced ```odin prelude|fires|silent blocks are the exemplar, the test and the
// documentation at once; the prose around them is the explain body and the block text.
// ponytail: the frontmatter is turned into one JSON5 object and fed to the existing loader, so
// there is exactly one validator for keys, enums and required fields.

Rule_File :: struct {
	frontmatter: string, // as a JSON5 object text
	prose:       string, // body minus the fenced blocks
	prelude:     string,
	fires:       string,
	silent:      string,
}

// parse_rule_file splits frontmatter, prose and the three fenced blocks. err names the defect.
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
		rf.frontmatter = frontmatter_to_json5(rest[:end])
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
				// an ordinary code sample: stays in the prose
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

// frontmatter_to_json5: `key: value` lines to one JSON5 object. Bare strings are quoted;
// inline objects, arrays, booleans and numbers pass through.
frontmatter_to_json5 :: proc(fm: string) -> string {
	b := strings.builder_make()
	strings.write_string(&b, "{\n")
	for l in strings.split_lines(fm, context.temp_allocator) {
		if strings.trim_space(l) == "" ||
		   strings.has_prefix(strings.trim_space(l), "//") {continue}
		key, sep, val := strings.partition(l, ":")
		if sep == "" {continue}
		key = strings.trim_space(key)
		val = strings.trim_space(val)
		strings.write_string(&b, "  ")
		strings.write_string(&b, key)
		strings.write_string(&b, ": ")
		switch {
		case val == "" || val == "true" || val == "false" || is_number(val) || val[0] == '"':
			strings.write_string(&b, val if val != "" else `""`)
		case val[0] == '{' || val[0] == '[':
			strings.write_string(&b, quote_bare_values(val))
		case:
			strings.write_byte(&b, '"')
			for c in val {
				if c == '"' || c == '\\' {strings.write_byte(&b, '\\')}
				strings.write_rune(&b, c)
			}
			strings.write_byte(&b, '"')
		}
		strings.write_string(&b, ",\n")
	}
	strings.write_string(&b, "}")
	return strings.to_string(b)
}

is_number :: proc(s: string) -> bool {
	if s == "" {return false}
	for c in s {if !(c >= '0' && c <= '9' || c == '.' || c == '-') {return false}}
	return true
}

// block_source: a fenced block as a compilable file: `#+` tags stay first, then the package
// clause, then the block. One prepended line, so a violation's line maps back as line-1.
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

// quote_bare_values: inside an inline object or array, a bare word in value position
// (`kind: vet_tag`, `["pure", edge]`) becomes a JSON5 string; keys, numbers, true/false/null
// and quoted strings pass through. Lets the frontmatter read like the spec instead of JSON.
quote_bare_values :: proc(src: string) -> string {
	b := strings.builder_make()
	i := 0
	for i < len(src) {
		c := src[i]
		switch {
		case c == '"' || c == '\'':
			j := i + 1
			for j < len(src) && src[j] != c {j += 1}
			strings.write_string(&b, src[i:min(j + 1, len(src))])
			i = j + 1
		case is_ident_char(c):
			j := i
			for j < len(src) && is_ident_char(src[j]) {j += 1}
			word := src[i:j]
			k := j
			for k < len(src) && src[k] == ' ' {k += 1}
			is_key := k < len(src) && src[k] == ':'
			if is_key || word == "true" || word == "false" || word == "null" || is_number(word) {
				strings.write_string(&b, word)
			} else {
				strings.write_byte(&b, '"')
				strings.write_string(&b, word)
				strings.write_byte(&b, '"')
			}
			i = j
		case:
			strings.write_byte(&b, c)
			i += 1
		}
	}
	return strings.to_string(b)
}

is_ident_char :: proc(c: byte) -> bool {
	return(
		c == '_' ||
		c == '.' ||
		c == '-' ||
		(c >= 'a' && c <= 'z') ||
		(c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9') \
	)
}
