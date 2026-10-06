package odx

import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strings"
import "core:unicode/utf8"

Ancestor :: struct {
	node:             ^ast.Node,
	child_depth:      int,
	opens_proc_frame: bool,
}

File_Walk :: struct {
	path:           string,
	src:            string,
	findings:       ^[dynamic]Finding,
	layout:         ^Layout,
	ancestors:      [dynamic]Ancestor,
	procs:          [dynamic]Proc_Frame,
	code_line_sums: []int,
}

// Runs every rule that reads the AST on `file`, and records in `layout` what `line-length` needs
// from the parse. The findings it appends borrow `path`. The working lists are allocated with
// `context.allocator`, and `layout` grows with its lists' own allocator. The caller sets the first
// to its scratch arena, where the `delete`s here do nothing and the caller's `arena_free_all`
// reclaims the lists.
walk_file :: proc(file: ^ast.File, path: string, findings: ^[dynamic]Finding, layout: ^Layout) {
	w := File_Walk {
		path           = path,
		src            = file.src,
		findings       = findings,
		layout         = layout,
		ancestors      = make([dynamic]Ancestor, context.allocator),
		procs          = make([dynamic]Proc_Frame, context.allocator),
		code_line_sums = code_line_prefix_sums(file.src, file.comments[:]),
	}
	defer {
		delete(w.ancestors)
		delete(w.procs)
		delete(w.code_line_sums)
	}
	check_block_comments(&w, file.comments[:])
	visitor := ast.Visitor {
		visit = visit_node,
		data  = &w,
	}
	for decl in file.decls {
		ast.walk(&visitor, decl)
	}
}

@(private = "file")
visit_node :: proc(v: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
	w := (^File_Walk)(v.data)
	if node == nil {
		if pop(&w.ancestors).opens_proc_frame {
			close_proc(w)
		}
		return nil
	}
	parent: ^ast.Node
	depth := 0
	opens_proc_frame := false
	if len(w.ancestors) > 0 {
		top := w.ancestors[len(w.ancestors) - 1]
		parent, depth = top.node, top.child_depth
	}
	check_bounds_check(
		w,
		node.pos,
		.Bounds_Check in node.state_flags,
		.No_Bounds_Check in node.state_flags,
	)
	#partial switch n in node.derived {
	case ^ast.Block_Stmt:
		is_body := is_proc_or_foreign_body(parent)
		check_block(w, n, is_body)
		if !is_body {
			depth += 1
			check_nesting_depth(w, n, depth)
		}
	case ^ast.Proc_Lit:
		depth = 0
		if n.body != nil {
			open_proc(w, n, parent)
			opens_proc_frame = true
		}
	case ^ast.Proc_Type:
		check_bounds_check(w, n.pos, .Bounds_Check in n.tags, .No_Bounds_Check in n.tags)
	case ^ast.Auto_Cast:
		report(w, .Auto_Cast, n.pos, AUTO_CAST_MESSAGE)
	case ^ast.Type_Cast:
		if n.tok.kind == .Transmute {
			report(w, .Transmute, n.tok.pos, TRANSMUTE_MESSAGE)
		}
	case ^ast.Branch_Stmt:
		if n.tok.kind == .Fallthrough {
			report(w, .Fallthrough, n.tok.pos, FALLTHROUGH_MESSAGE)
		}
	case ^ast.Struct_Type:
		record_struct_gaps(w.layout, w.src, n.fields)
	case ^ast.Bit_Field_Type:
		record_bit_field_gaps(w.layout, w.src, n.fields)
	case ^ast.Enum_Type:
		record_value_gaps(w.layout, w.src, n.fields)
	case ^ast.Comp_Lit:
		record_value_gaps(w.layout, w.src, n.elems)
	case ^ast.Value_Decl:
		if in_foreign_block(w) && strings.has_suffix(w.src[n.pos.offset:n.end.offset], "---") {
			append(&w.layout.foreign_decl_lines, Line_Run{n.pos.line, n.end.line})
		}
	}
	append(&w.ancestors, Ancestor{node, depth, opens_proc_frame})
	return v
}

@(private = "file")
is_proc_or_foreign_body :: proc(parent: ^ast.Node) -> bool {
	if parent == nil {
		return false
	}
	#partial switch _ in parent.derived {
	case ^ast.Proc_Lit, ^ast.Foreign_Block_Decl:
		return true
	}
	return false
}

// Foreign blocks often sit inside file-scope `when` statements, so any ancestor counts.
@(private = "file")
in_foreign_block :: proc(w: ^File_Walk) -> bool {
	for ancestor in w.ancestors {
		if _, is_foreign := ancestor.node.derived.(^ast.Foreign_Block_Decl); is_foreign {
			return true
		}
	}
	return false
}

// `message` must outlive the findings.
report :: proc(w: ^File_Walk, rule: Rule, pos: tokenizer.Pos, message: string) {
	line, col := source_position(w.src, pos)
	append(
		w.findings,
		Finding{path = w.path, line = line, col = col, rule = rule, message = message},
	)
}

// The tokenizer's column counts bytes, and a finding's counts code points.
source_position :: proc(src: string, pos: tokenizer.Pos) -> (line, col: int) {
	before := src[:pos.offset]
	line_start := strings.last_index_byte(before, '\n') + 1
	return pos.line, 1 + utf8.rune_count_in_string(strings.trim_prefix(before[line_start:], BOM))
}
