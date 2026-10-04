package odx

import "base:runtime"
import "core:fmt"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

Ignore :: struct {
	line:   int,
	col:    int,
	rules:  bit_set[Rule],
	reason: string,
	covers: []Line_Run,
	used:   bool,
}

Line_Run :: struct {
	first, last: int,
}

@(private = "file", rodata)
WHOLE_FILE := [1]Line_Run{{1, max(int)}}

@(private = "file")
NOT_OWN_LINE :: "an ignore must be on its own line, above the code it covers"
@(private = "file")
NO_SPACE :: "write an ignore as '// odx:ignore <rules> <reason>', with one space after '//'"
@(private = "file")
ONE_SPACE :: "put exactly one space between 'odx:ignore' and its rules"
@(private = "file")
NO_RULE :: "this ignore names no rule"
@(private = "file")
SPACE_IN_LIST :: "the rule list has a space in it; write rules as 'a,b' with no spaces"
@(private = "file")
EMPTY_ITEM :: "the rule list has an empty item; separate rules with single commas"
@(private = "file")
NO_REASON :: "this ignore has no reason after its rules"
@(private = "file")
UNPARSABLE :: "only whole-file ignores apply in a file odx can't parse"
@(private = "file")
NO_TARGET :: "this ignore binds to nothing; put it directly above the code it covers"
@(private = "file")
UNUSED :: "this ignore suppressed no finding; remove it"

read_ignores :: proc(
	file: ^Source_File,
	src: string,
	tree: ^ast.File,
	package_offset: int,
	allocator, scratch: runtime.Allocator,
) {
	line_starts := make_line_starts(src, scratch)
	binder: Maybe(Binder)
	t: tokenizer.Tokenizer
	tokenizer.init(&t, src, "", nil)
	for token := tokenizer.scan(&t); token.kind != .EOF; token = tokenizer.scan(&t) {
		if is_triple_quote_start(src, token) {
			t.read_offset = triple_quote_end(src, token.pos.offset + len(`"""`))
			tokenizer.advance_rune(&t)
			continue
		}
		if token.kind != .Comment || !is_odx_directive(token.text) {
			continue
		}
		offset := token.pos.offset
		line := line_of(line_starts, offset)
		before := strings.trim_prefix(src[line_starts[line - 1]:offset], BOM)
		ignore, problem := parse_ignore(token.text, allocator)
		ignore.line = line
		ignore.col = 1 + utf8.rune_count_in_string(before)
		switch {
		case problem != "":
		case strings.trim_left(before, " \t") != "":
			problem = NOT_OWN_LINE
		case offset < package_offset:
			ignore.covers = WHOLE_FILE[:]
		case tree == nil:
			problem = UNPARSABLE
		case:
			if binder == nil {
				binder = make_binder(src, line_starts, tree, scratch)
			}
			bound: bool
			ignore.covers, bound = bind(binder.?, offset, allocator, scratch)
			if !bound {
				problem = NO_TARGET
			}
		}
		if problem != "" {
			append(
				&file.findings,
				Finding {
					path = file.path,
					line = ignore.line,
					col = ignore.col,
					rule = .Ignore_Invalid,
					message = problem,
				},
			)
			continue
		}
		append(&file.ignores, ignore)
	}
}

// core:odin's tokenizer doesn't know the compiler's `"""` strings: it reads `""` and then lines
// of the string as code, so an ignore written inside one would be reported.
@(private = "file")
is_triple_quote_start :: proc(src: string, token: tokenizer.Token) -> bool {
	end := token.pos.offset + len(token.text)
	return token.kind == .String && token.text == `""` && end < len(src) && src[end] == '"'
}

// Returns the offset just past the closing `"""`, or the end of `src` if there is none.
@(private = "file")
triple_quote_end :: proc(src: string, from: int) -> int {
	for i := from; i < len(src); i += 1 {
		switch {
		case src[i] == '\\':
			i += 1
		case strings.has_prefix(src[i:], `"""`):
			return i + len(`"""`)
		}
	}
	return len(src)
}

// Any comment that reads as an attempt at a directive is one, so a misspelled ignore is reported
// instead of silently suppressing nothing.
@(private = "file")
is_odx_directive :: proc(comment: string) -> bool {
	text := strings.trim_left_space(strings.trim_left(comment, "/*"))
	return len(text) >= len("odx:") && strings.equal_fold(text[:len("odx:")], "odx:")
}

// Returns either a valid ignore or a problem, never both. The reason or the problem is allocated
// with `allocator` and owned by the caller. The caller fills in `line`, `col` and `covers`.
@(private = "file")
parse_ignore :: proc(
	comment: string,
	allocator: runtime.Allocator,
) -> (
	ignore: Ignore,
	problem: string,
) {
	if !strings.has_prefix(comment, "// odx:") {
		return {}, strings.clone(NO_SPACE, allocator)
	}
	directive := comment[len("// "):]
	name_end := strings.index_any(directive, " \t")
	if name_end < 0 {
		name_end = len(directive)
	}
	if name := directive[:name_end]; name != "odx:ignore" {
		message := "unknown directive '%s'; the only one is odx:ignore"
		return {}, fmt.aprintf(message, name, allocator = allocator)
	}
	rest := directive[name_end:]
	switch {
	case strings.trim_space(rest) == "":
		return {}, strings.clone(NO_RULE, allocator)
	case rest[0] != ' ' || rest[1] == ' ' || rest[1] == '\t':
		return {}, strings.clone(ONE_SPACE, allocator)
	}
	rest = rest[1:]
	list, reason := rest, ""
	if list_end := strings.index_any(rest, " \t"); list_end >= 0 {
		list, reason = rest[:list_end], strings.trim_space(rest[list_end:])
	}
	switch {
	case strings.has_suffix(list, ",") && reason != "", strings.has_prefix(reason, ","):
		return {}, strings.clone(SPACE_IN_LIST, allocator)
	case strings.has_prefix(list, ","),
	     strings.has_suffix(list, ","),
	     strings.contains(list, ",,"):
		return {}, strings.clone(EMPTY_ITEM, allocator)
	}
	ignore.rules, problem = parse_rules(list, allocator)
	if problem != "" {
		return {}, problem
	}
	if reason == "" {
		return {}, strings.clone(NO_REASON, allocator)
	}
	ignore.reason = strings.clone(reason, allocator)
	return
}

@(private = "file")
parse_rules :: proc(
	list: string,
	allocator: runtime.Allocator,
) -> (
	rules: bit_set[Rule],
	problem: string,
) {
	ids := list
	for id in strings.split_iterator(&ids, ",") {
		if id == "all" {
			for info, rule in RULES {
				if info.ignorable {
					rules += {rule}
				}
			}
			continue
		}
		rule, known := rule_by_id(id)
		if !known {
			return {}, fmt.aprintf("unknown rule '%s'", id, allocator = allocator)
		}
		if !RULES[rule].ignorable {
			return {}, fmt.aprintf("rule '%s' can't be ignored", id, allocator = allocator)
		}
		rules += {rule}
	}
	return
}

@(private = "file")
rule_by_id :: proc(id: string) -> (rule: Rule, known: bool) {
	for info, r in RULES {
		if info.id == id {
			return r, true
		}
	}
	return
}

@(private = "file")
FILE_SCOPE :: -1

@(private = "file")
Node_Span :: struct {
	node:            ^ast.Node,
	parent:          int,
	depth:           int,
	last_descendant: int,
	first_line:      int,
	last_line:       int,
}

Binder :: struct {
	src:         string,
	line_starts: []int,
	preorder:    [dynamic]Node_Span,
}

// The caller owns the binder's `preorder`, allocated with `allocator`. The binder borrows `src`,
// `line_starts` and `tree`, so it must not outlive them.
//
// Skips comment groups: core:odin puts consecutive comments in one `Comment_Group` node, so a
// stacked ignore would otherwise bind inside its own group.
make_binder :: proc(
	src: string,
	line_starts: []int,
	tree: ^ast.File,
	allocator: runtime.Allocator,
) -> Binder {
	walk := Node_Walk {
		binder = {
			src = src,
			line_starts = line_starts,
			preorder = make([dynamic]Node_Span, allocator),
		},
		ancestors = make([dynamic]int, allocator),
	}
	defer delete(walk.ancestors)
	visitor := ast.Visitor {
		visit = record_node,
		data  = &walk,
	}
	for decl in tree.decls {
		ast.walk(&visitor, decl)
	}
	return walk.binder
}

@(private = "file")
Node_Walk :: struct {
	binder:    Binder,
	ancestors: [dynamic]int,
}

@(private = "file")
record_node :: proc(v: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
	w := (^Node_Walk)(v.data)
	nodes := &w.binder.preorder
	if node == nil {
		nodes[pop(&w.ancestors)].last_descendant = len(nodes) - 1
		return nil
	}
	if _, is_comment := node.derived.(^ast.Comment_Group); is_comment {
		return nil
	}
	line_starts := w.binder.line_starts
	append(
		nodes,
		Node_Span {
			node = node,
			parent = slice.last(w.ancestors[:]) if len(w.ancestors) > 0 else FILE_SCOPE,
			depth = len(w.ancestors),
			first_line = line_of(line_starts, node.pos.offset),
			last_line = line_of(line_starts, max(node.end.offset - 1, node.pos.offset)),
		},
	)
	append(&w.ancestors, len(nodes) - 1)
	return v
}

bind :: proc(
	b: Binder,
	offset: int,
	allocator, scratch: runtime.Allocator,
) -> (
	covers: []Line_Run,
	bound: bool,
) {
	target, found := first_child_after(b, innermost_container(b, offset), offset)
	if found {
		if _, is_list := b.preorder[target].node.derived.(^ast.Field_List); is_list {
			target, found = first_child_after(b, target, offset)
		}
	}
	if !found {
		return nil, false
	}

	span := b.preorder[target]
	own := own_body(span.node)
	holes := make([dynamic]Line_Run, scratch)
	for n in b.preorder[target:span.last_descendant + 1] {
		if n.node == own {
			continue
		}
		if hole, is_body := body_hole(b, n.node); is_body {
			append(&holes, hole)
		}
	}
	if clause, is_clause := span.node.derived.(^ast.Case_Clause); is_clause {
		header_end := line_of(b.line_starts, clause.terminator.pos.offset)
		append(&holes, Line_Run{header_end + 1, span.last_line})
	}
	slice.sort_by(holes[:], proc(x, y: Line_Run) -> bool {return x.first < y.first})

	runs := make([dynamic]Line_Run, allocator)
	next := line_of(b.line_starts, offset) + 1
	for hole in holes {
		if hole.first > hole.last {
			continue
		}
		if hole.first > next {
			append(&runs, Line_Run{next, hole.first - 1})
		}
		next = max(next, hole.last + 1)
	}
	if next <= span.last_line {
		append(&runs, Line_Run{next, span.last_line})
	}
	return runs[:], true
}

@(private = "file")
innermost_container :: proc(b: Binder, offset: int) -> (container: int) {
	container = FILE_SCOPE
	smallest := max(int)
	for n, i in b.preorder {
		start, end := n.node.pos.offset, n.node.end.offset
		if start >= offset || offset >= end {
			continue
		}
		size := end - start
		if size < smallest || (size == smallest && n.depth > b.preorder[container].depth) {
			container, smallest = i, size
		}
	}
	return
}

// A literal element, keyed or not and with or without `&`, covers its own literal's lines
// (operator decision 2026-10-03).
@(private = "file")
own_body :: proc(target: ^ast.Node) -> ^ast.Node {
	literal := target
	if keyed, is_keyed := target.derived.(^ast.Field_Value); is_keyed {
		literal = keyed.value
	}
	if address, is_unary := literal.derived.(^ast.Unary_Expr);
	   is_unary && address.op.kind == .And {
		literal = address.expr
	}
	if _, is_literal := literal.derived.(^ast.Comp_Lit); is_literal {
		return literal
	}
	return nil
}

@(private = "file")
first_child_after :: proc(b: Binder, parent, offset: int) -> (child: int, found: bool) {
	first, last := 0, len(b.preorder) - 1
	if parent != FILE_SCOPE {
		first, last = parent + 1, b.preorder[parent].last_descendant
	}
	for i in first ..= last {
		n := b.preorder[i].node
		if b.preorder[i].parent == parent &&
		   n.pos.offset > offset &&
		   (!found || n.pos.offset < b.preorder[child].node.pos.offset) {
			child, found = i, true
		}
	}
	return
}

@(private = "file")
body_hole :: proc(b: Binder, node: ^ast.Node) -> (hole: Line_Run, is_body: bool) {
	open, close: int
	#partial switch n in node.derived {
	case ^ast.Block_Stmt:
		open, close = n.open.offset, n.close.offset
	case ^ast.Comp_Lit:
		open, close = n.open.offset, n.close.offset
	case ^ast.Struct_Type:
		header := [?]^ast.Node {
			n.poly_params,
			n.align,
			n.min_field_align,
			n.max_field_align,
			last_where(n.where_clauses),
		}
		open, close = open_brace_after(b.src, n.pos.offset, header[:]), n.end.offset - 1
	case ^ast.Enum_Type:
		open, close = n.open.offset, n.close.offset
	case ^ast.Bit_Field_Type:
		open, close = n.open.offset, n.close.offset
	case ^ast.Union_Type:
		header := [?]^ast.Node{n.poly_params, n.align, last_where(n.where_clauses)}
		open, close = open_brace_after(b.src, n.pos.offset, header[:]), n.end.offset - 1
	case:
		return {}, false
	}
	return {line_of(b.line_starts, open) + 1, line_of(b.line_starts, close) - 1}, true
}

// The parser doesn't record where a struct's or union's `{` is, so this finds the first one after
// the last part of its header.
@(private = "file")
open_brace_after :: proc(src: string, keyword: int, header: []^ast.Node) -> int {
	from := keyword
	for part in header {
		if part != nil {
			from = max(from, part.end.offset)
		}
	}
	t: tokenizer.Tokenizer
	tokenizer.init(&t, src[from:], "", nil)
	for token := tokenizer.scan(&t); token.kind != .EOF; token = tokenizer.scan(&t) {
		if token.kind == .Open_Brace {
			return from + token.pos.offset
		}
	}
	return len(src)
}

@(private = "file")
last_where :: proc(clauses: []^ast.Expr) -> ^ast.Expr {
	return clauses[len(clauses) - 1] if len(clauses) > 0 else nil
}

make_line_starts :: proc(src: string, allocator: runtime.Allocator) -> []int {
	starts := make([dynamic]int, allocator)
	append(&starts, 0)
	for c, i in transmute([]byte)src {
		if c == '\n' {
			append(&starts, i + 1)
		}
	}
	return starts[:]
}

@(private = "file")
line_of :: proc(line_starts: []int, offset: int) -> int {
	i, found := slice.binary_search(line_starts, offset)
	return i + 1 if found else i
}

apply_ignores :: proc(packages: []Package, result: ^Result) {
	files := make(map[string]^Source_File, context.temp_allocator)
	for &pkg in packages {
		for &file in pkg.files {
			if len(file.ignores) > 0 {
				files[file.path] = &file
			}
		}
	}
	if len(files) == 0 {
		return
	}
	kept := 0
	for f in result.findings {
		if file, has := files[f.path]; has && RULES[f.rule].ignorable {
			if ignore := last_covering(file.ignores[:], f); ignore != nil {
				ignore.used = true
				if !f.held_back {
					result.ignored += 1
				}
				continue
			}
		}
		result.findings[kept] = f
		kept += 1
	}
	resize(&result.findings, kept)

	for pkg in packages {
		for file in pkg.files {
			for ignore in file.ignores {
				if !ignore.used {
					add_rule_finding(
						result,
						pkg,
						{
							path = file.path,
							line = ignore.line,
							col = ignore.col,
							rule = .Ignore_Unused,
							message = UNUSED,
						},
					)
				}
			}
		}
	}
}

@(private = "file")
last_covering :: proc(ignores: []Ignore, f: Finding) -> ^Ignore {
	#reverse for &ignore in ignores {
		if f.rule not_in ignore.rules {
			continue
		}
		for run in ignore.covers {
			if run.first <= f.line && f.line <= run.last {
				return &ignore
			}
		}
	}
	return nil
}
