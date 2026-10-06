package odx

import "core:fmt"
import "core:odin/ast"
import "core:odin/tokenizer"

PROC_LINE_LIMIT :: 100
NESTING_LIMIT :: 6

Proc_Frame :: struct {
	finding_pos:          tokenizer.Pos,
	open_line:            int,
	close_line:           int,
	nested_literal_lines: int,
}

// The caller owns the slice, allocated with `context.allocator`.
code_line_prefix_sums :: proc(src: string, comments: []^ast.Comment_Group) -> []int {
	counter := Line_Counter {
		counts = make([dynamic]int, 1, context.allocator),
	}
	offset := 0
	for group in comments {
		for comment in group.list {
			count_span(&counter, src[offset:comment.pos.offset], true)
			offset = comment.pos.offset + len(comment.text)
			count_span(&counter, src[comment.pos.offset:offset], false)
		}
	}
	count_span(&counter, src[offset:], true)
	end_line(&counter)
	return counter.counts[:]
}

@(private = "file")
Line_Counter :: struct {
	counts:        [dynamic]int,
	line_has_code: bool,
}

@(private = "file")
count_span :: proc(counter: ^Line_Counter, text: string, is_code: bool) {
	for i in 0 ..< len(text) {
		switch text[i] {
		case '\n':
			end_line(counter)
		case ' ', '\t', '\r':
		case:
			counter.line_has_code ||= is_code
		}
	}
}

@(private = "file")
end_line :: proc(counter: ^Line_Counter) {
	last := counter.counts[len(counter.counts) - 1]
	append(&counter.counts, last + int(counter.line_has_code))
	counter.line_has_code = false
}

@(private = "file")
counted_between :: proc(sums: []int, open_line, close_line: int) -> int {
	if close_line <= open_line {
		return 0
	}
	return sums[close_line - 1] - sums[open_line]
}

open_proc :: proc(w: ^File_Walk, lit: ^ast.Proc_Lit, parent: ^ast.Node) {
	frame := Proc_Frame {
		finding_pos = lit.type.tok.pos,
		open_line   = lit.body.pos.line,
		close_line  = lit.body.end.line,
	}
	decl: ^ast.Value_Decl
	if parent != nil {
		decl, _ = parent.derived.(^ast.Value_Decl)
	}
	if decl != nil {
		for value, i in decl.values {
			if bound, is_proc := value.derived.(^ast.Proc_Lit);
			   is_proc && bound == lit && i < len(decl.names) {
				frame.finding_pos = decl.names[i].pos
			}
		}
	}
	append(&w.procs, frame)
}

// The message is allocated with the findings' allocator.
close_proc :: proc(w: ^File_Walk) {
	frame := pop(&w.procs)
	between_braces := counted_between(w.code_line_sums, frame.open_line, frame.close_line)
	if len(w.procs) > 0 {
		w.procs[len(w.procs) - 1].nested_literal_lines += between_braces
	}
	counted := between_braces - frame.nested_literal_lines
	if counted <= PROC_LINE_LIMIT {
		return
	}
	message := fmt.aprintf(
		"this procedure has %d counted lines, over the limit of %d",
		counted,
		PROC_LINE_LIMIT,
		allocator = w.findings.allocator,
	)
	report(w, .Proc_Length, frame.finding_pos, message)
}

// Reports each block that first crosses the limit and none of the blocks inside it, so one ignore
// covers one block. The message is allocated with the findings' allocator.
check_nesting_depth :: proc(w: ^File_Walk, block: ^ast.Block_Stmt, block_depth: int) {
	if block_depth != NESTING_LIMIT + 1 || len(w.procs) == 0 {
		return
	}
	message := fmt.aprintf(
		"this block is at depth %d, over the limit of %d",
		block_depth,
		NESTING_LIMIT,
		allocator = w.findings.allocator,
	)
	report(w, .Nesting_Depth, block.pos, message)
}
