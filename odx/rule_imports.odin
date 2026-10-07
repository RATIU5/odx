package odx

import "core:fmt"
import "core:odin/ast"
import "core:strconv"
import "core:strings"

Import_Group :: enum u8 {
	Base_Core,
	Vendor,
	Collection,
	Relative,
}

@(private = "file", rodata)
IMPORT_GROUPS := [?]struct {
	prefix: string,
	group:  Import_Group,
}{{"base:", .Base_Core}, {"core:", .Base_Core}, {"vendor:", .Vendor}}

@(private = "file", rodata)
IMPORT_GROUP_LABELS := [Import_Group]string {
	.Base_Core  = "base or core",
	.Vendor     = "vendor",
	.Collection = "collection",
	.Relative   = "relative",
}

Import_Break :: enum u8 {
	None,
	Out_Of_Order,
	Group_Split,
	Groups_Not_Separated,
}

import_group :: proc(path: string) -> Import_Group {
	for row in IMPORT_GROUPS {
		if strings.has_prefix(path, row.prefix) {
			return row.group
		}
	}
	return .Collection if strings.contains(path, ":") else .Relative
}

import_step :: proc(prev, next: Import_Group, blanks, non_blanks: int) -> Import_Break {
	switch {
	case next < prev:
		return .Out_Of_Order
	case next == prev:
		return .None if blanks + non_blanks == 0 else .Group_Split
	}
	return .None if blanks == 1 && non_blanks == 0 else .Groups_Not_Separated
}

// The name the compiler gives an import without an alias: the directory's name, whatever the
// package inside declares.
unaliased_import_name :: proc(path: string) -> string {
	return path[strings.last_index_any(path, "/:") + 1:]
}

// An escaped path is unquoted with `context.allocator`.
@(private = "file")
import_path :: proc(decl: ^ast.Import_Decl) -> (path: string, ok: bool) {
	path, _, ok = strconv.unquote_string(decl.relpath.text)
	return
}

// The parser gives an import without an alias no name token. The message is allocated with the
// findings' allocator.
check_import_names :: proc(w: ^File_Walk, decl: ^ast.Import_Decl) {
	if decl.name.kind != .Ident {
		return
	}
	alias := decl.name.text
	check_name(w, alias, decl.name.pos, .Import_Alias)
	path, unquoted := import_path(decl)
	if !unquoted || alias != unaliased_import_name(path) {
		return
	}
	message := fmt.aprintf(
		"alias '%s' is the name this import has without an alias",
		alias,
		allocator = w.findings.allocator,
	)
	report(w, .Import_Alias, decl.name.pos, message)
}

// Judges the order of the groups and the blank lines between imports. Order inside a group is the
// formatter's. Each message is allocated with the findings' allocator.
check_import_order :: proc(w: ^File_Walk, decls: []^ast.Stmt) {
	prev: ^ast.Import_Decl
	prev_group: Import_Group
	for decl in decls {
		next, is_import := decl.derived.(^ast.Import_Decl)
		if !is_import {
			prev = nil
			continue
		}
		path, unquoted := import_path(next)
		if !unquoted {
			prev = nil
			continue
		}
		group := import_group(path)
		if prev != nil {
			blanks, non_blanks := gap_lines(w.src, prev.end.offset, import_start(next))
			was, now := IMPORT_GROUP_LABELS[prev_group], IMPORT_GROUP_LABELS[group]
			allocator := w.findings.allocator
			message: string
			switch import_step(prev_group, group, blanks, non_blanks) {
			case .None:
			case .Out_Of_Order:
				message = fmt.aprintf(
					"a %s import comes after a %s import",
					now,
					was,
					allocator = allocator,
				)
			case .Group_Split:
				message = fmt.aprintf(
					"two %s imports have a line between them",
					now,
					allocator = allocator,
				)
			case .Groups_Not_Separated:
				message = fmt.aprintf(
					"a %s import and a %s import aren't separated by one blank line",
					was,
					now,
					allocator = allocator,
				)
			}
			if message != "" {
				report(w, .Import_Order, next.import_tok.pos, message)
			}
		}
		prev, prev_group = next, group
	}
}

@(private = "file")
import_start :: proc(decl: ^ast.Import_Decl) -> int {
	start := decl.import_tok.pos.offset
	for attribute in decl.attributes {
		start = min(start, attribute.pos.offset)
	}
	return start
}

// Counts the lines between two imports, without the `//` lines directly above the second one, which
// belong to it.
@(private = "file")
gap_lines :: proc(src: string, from, to: int) -> (blanks, non_blanks: int) {
	first := strings.index_byte(src[from:to], '\n')
	if first < 0 {
		return
	}
	between := src[from + first + 1:strings.last_index_byte(src[:to], '\n') + 1]
	comments := 0
	for line in strings.split_lines_iterator(&between) {
		text := strings.trim_space(line)
		if strings.has_prefix(text, "//") {
			comments += 1
			continue
		}
		non_blanks += comments
		comments = 0
		if text == "" {
			blanks += 1
		} else {
			non_blanks += 1
		}
	}
	return
}
