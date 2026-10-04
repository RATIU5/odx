package odx

import "core:fmt"
import "core:strings"

LINE_LIMIT :: 100
TAB_WIDTH :: 4
BOM :: "\ufeff"

check_line_length :: proc(findings: ^[dynamic]Finding, path, src: string) {
	text := strings.trim_prefix(src, BOM)
	line_number := 0
	// The iterator drops a line's trailing `\r`.
	for line in strings.split_lines_iterator(&text) {
		line_number += 1
		width, col, code_points := 0, 0, 0
		for r in line {
			code_points += 1
			width += TAB_WIDTH if r == '\t' else 1
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
