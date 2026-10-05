package odx

import "core:fmt"
import "core:odin/ast"
import "core:slice"
import "core:strings"

LINE_LIMIT :: 100
TAB_WIDTH :: 4
BOM :: "\ufeff"

Alignment_Gap :: struct {
	byte_offset: int,
	len:         int,
}

// What the parse tells `line-length` about a file's layout, per Appendix E.8. Empty for a file the
// parser can't read, which is then measured as written.
Layout :: struct {
	gaps:               [dynamic]Alignment_Gap,
	foreign_decl_lines: [dynamic]Line_Run,
}

// Measures a tab as `TAB_WIDTH` columns, each of `layout`'s gaps as one column and every other code
// point as one, and skips `layout`'s `foreign` declaration lines. Each message is allocated with
// `findings`' allocator, and the findings borrow `path`.
check_line_length :: proc(findings: ^[dynamic]Finding, path, src: string, layout: Layout) {
	// The walk records a literal's own gaps before the gaps of the literals nested in it.
	gaps := layout.gaps[:]
	slice.sort_by(gaps, proc(a, b: Alignment_Gap) -> bool {return a.byte_offset < b.byte_offset})
	skipped := layout.foreign_decl_lines[:]

	rest := strings.trim_prefix(src, BOM)
	line_number := 0
	for len(rest) > 0 {
		line := rest
		next := len(rest)
		if end := strings.index_byte(rest, '\n'); end >= 0 {
			line, next = rest[:end], end + 1
		}
		start := len(src) - len(rest)
		rest = rest[next:]
		line = strings.trim_suffix(line, "\r")
		line_number += 1

		for len(skipped) > 0 && skipped[0].last < line_number {
			skipped = skipped[1:]
		}
		if len(skipped) > 0 && skipped[0].first <= line_number {
			continue
		}

		width, col, code_points := 0, 0, 0
		for r, i in line {
			offset := start + i
			for len(gaps) > 0 && gaps[0].byte_offset + gaps[0].len <= offset {
				gaps = gaps[1:]
			}
			code_points += 1
			switch {
			case len(gaps) > 0 && gaps[0].byte_offset < offset:
			case r == '\t':
				width += TAB_WIDTH
			case:
				width += 1
			}
			if col == 0 && width > LINE_LIMIT {
				col = code_points
			}
		}
		if col == 0 {
			continue
		}
		message := fmt.aprintf(
			"line is %d columns wide, over the limit of %d",
			width,
			LINE_LIMIT,
			allocator = findings.allocator,
		)
		append(
			findings,
			Finding {
				path = path,
				line = line_number,
				col = col,
				rule = .Line_Length,
				message = message,
			},
		)
	}
}

record_struct_gaps :: proc(layout: ^Layout, src: string, fields: ^ast.Field_List) {
	for field in fields.list {
		record_gap_after_colon(layout, src, field.type.pos.offset)
	}
}

record_bit_field_gaps :: proc(layout: ^Layout, src: string, fields: []^ast.Bit_Field_Field) {
	for field in fields {
		record_gap_after_colon(layout, src, field.type.pos.offset)
		pipe := field.bit_size.pos.offset - 1
		for src[pipe] == ' ' {
			pipe -= 1
		}
		if src[pipe] == '|' {
			record_gap(layout, src, field.type.end.offset, pipe)
		}
	}
}

record_value_gaps :: proc(layout: ^Layout, src: string, elems: []^ast.Expr) {
	for elem in elems {
		if value, named := elem.derived.(^ast.Field_Value); named {
			record_gap(layout, src, value.field.end.offset, value.sep.offset)
		}
	}
}

@(private = "file")
record_gap_after_colon :: proc(layout: ^Layout, src: string, type_offset: int) {
	colon := type_offset - 1
	for src[colon] == ' ' {
		colon -= 1
	}
	if src[colon] == ':' {
		record_gap(layout, src, colon + 1, type_offset)
	}
}

@(private = "file")
record_gap :: proc(layout: ^Layout, src: string, from, to: int) {
	if to - from < 2 || strings.trim_left(src[from:to], " ") != "" {
		return
	}
	append(&layout.gaps, Alignment_Gap{from, to - from})
}
