package odx

import "base:runtime"
import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:strings"

// The part of a file before its declarations, read with the tokenizer so a file the parser can't
// read still has one.
Header :: struct {
	// Each `#+` tag's text after the `#+`.
	tags:           [dynamic]string,
	// The identifier after the first `package` token, or "" when there is none.
	name:           string,
	// The byte offset of that `package` token, or -1.
	package_offset: int,
}

// The tags and name borrow from `src`. Allocates the tag list with `allocator`.
scan_header :: proc(src: string, allocator: runtime.Allocator) -> (header: Header) {
	header.tags = make([dynamic]string, allocator)
	header.package_offset = -1
	t: tokenizer.Tokenizer
	tokenizer.init(&t, src, "", nil)
	for {
		token := tokenizer.scan(&t)
		#partial switch token.kind {
		case .EOF:
			return
		case .File_Tag:
			// The compiler's tokenizer ends a tag at any `/`, where core's ends it only at a comment.
			text := token.text[len("#+"):]
			if i := strings.index_byte(text, '/'); i >= 0 {
				text = text[:i]
			}
			append(&header.tags, text)
		case .Package:
			header.package_offset = token.pos.offset
			if next := tokenizer.scan(&t); next.kind == .Ident {
				header.name = next.text
			}
			return
		}
	}
}

Parse_Error :: struct {
	offset:  int,
	message: string,
}

// Parses `src` with `core:odin/parser` and returns its AST, or the error at the smallest offset that
// the parser or its tokenizer reports. `parse_file` returns true even when it reports errors (probe P5).
// The AST is allocated with `context.allocator`, which suits a scratch arena, and the error's message
// with `allocator`.
parse_source :: proc(
	src: string,
	allocator: runtime.Allocator,
) -> (
	file: ^ast.File,
	failure: Maybe(Parse_Error),
) {
	first: Maybe(Parse_Error)
	p := parser.default_parser()
	p.warn = nil
	// The handler gets no user data, so the capture travels in the context.
	p.err = proc(pos: tokenizer.Pos, msg: string, args: ..any) {
		first := (^Maybe(Parse_Error))(context.user_ptr)
		if e, found := first^.?; found && e.offset <= pos.offset {
			return
		}
		first^ = Parse_Error{pos.offset, fmt.aprintf(msg, ..args)}
	}
	file = new(ast.File)
	file.src = src
	context.user_ptr = &first
	parser.parse_file(&p, file)
	e, found := first.?
	if !found {
		return file, nil
	}
	return nil, Parse_Error{e.offset, strings.clone(e.message, allocator)}
}
