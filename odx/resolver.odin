package odx

import "base:runtime"
import "core:mem/virtual"
import "core:odin/ast"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

// What a name stands for, as far as the case of an alias needs it.
Kind :: enum u8 {
	Unknown,
	Type,
	// A parametric struct or union, so a call on it is a type.
	Poly_Type,
	Proc,
	// A built-in or intrinsic procedure that returns a type, so a call on it is a type.
	Type_Proc,
	Value,
	// Also an expression that is neither a type nor a constant, such as a field or an index.
	Variable,
}

// A call's kind, by its callee's kind.
@(private = "file", rodata)
CALL_KINDS := [Kind]Kind {
	.Unknown   = .Unknown,
	.Type      = .Value,
	.Poly_Type = .Type,
	.Proc      = .Value,
	.Type_Proc = .Type,
	.Value     = .Value,
	.Variable  = .Value,
}

Symbol_State :: enum u8 {
	Fresh,
	Resolving,
	Done,
}

// One declaration of a name. An untyped constant starts `Fresh` and takes the kind of its value,
// and one that is reached again while `Resolving` is in a cycle.
Symbol :: struct {
	decl:          ^ast.Value_Decl,
	value_index:   int,
	file:          ^File_Scope,
	// How many of the procedure scopes the declaration sees, its own included. 0 at package level.
	scope_count:   int,
	// The offset a variable is in scope from. A constant is in scope before its declaration too.
	visible_from:  int,
	// A parameter, a result or a variable that isn't static, which a procedure literal nested in
	// its procedure can't name.
	own_proc_only: bool,
	kind:          Kind,
	state:         Symbol_State,
}

// A name has one symbol per declaration, since platform files and `when` branches may each
// declare it.
Symbol_Table :: map[string][dynamic]Symbol

Package_Symbols :: map[string]Kind

Loaded_Package :: struct {
	symbols: Package_Symbols,
	// The declarations, until every symbol is resolved and `symbols` is complete.
	parsed:  ^Parsed_Package,
}

Parsed_Package :: struct {
	// Holds the sources, the ASTs and the table.
	arena:    virtual.Arena,
	declared: Symbol_Table,
}

Import :: struct {
	// Unquoted, as the source spells it.
	path:      string,
	looked_up: bool,
	// Nil for a path odx doesn't follow, and for a `foreign import`.
	pkg:       ^Loaded_Package,
}

File_Scope :: struct {
	pkg:     ^Loaded_Package,
	// The real directory its relative imports resolve from.
	dir:     string,
	imports: map[string]Import,
}

Scope :: struct {
	lit:       ^ast.Proc_Lit,
	collected: bool,
	locals:    Symbol_Table,
}

// Where a name is used: the file, how many of the procedure scopes enclose the use, and its offset.
@(private = "file")
Use :: struct {
	file:        ^File_Scope,
	scope_count: int,
	offset:      int,
}

Universe_Entry :: struct {
	name: string,
	kind: Kind,
}

// The names the compiler declares itself: `base:builtin` with the `@(builtin)` declarations of
// `base:runtime`, which every file sees, and `base:intrinsics`, which a file imports.
Universe :: struct {
	compiler:   string,
	builtin:    []Universe_Entry,
	intrinsics: []Universe_Entry,
}

universe_for :: proc(compiler: string) -> (universe: Universe, found: bool) {
	for candidate in UNIVERSES {
		if candidate.compiler == compiler {
			return candidate, true
		}
	}
	return {}, false
}

// Resolves the right side of `X :: Y` and `X :: Y(...)` to a kind through declarations alone. It
// must stay where `resolver_init` set it up, because imports point at its universe packages.
Resolver :: struct {
	// As `odin root` printed it, or "" when imports of the Odin root's collections stay unresolved.
	odin_root:   string,
	collections: []Collection,
	builtin:     Loaded_Package,
	intrinsics:  Loaded_Package,
	// Keyed by the directory's real path, so a package is read once however it is imported.
	cache:       map[string]^Loaded_Package,
	// The cached packages that still hold their declarations.
	unresolved:  [dynamic]^Loaded_Package,
	// One per procedure literal that encloses the walk's position, outermost first.
	scopes:      [dynamic]Scope,
	allocator:   runtime.Allocator,
}

// The resolver borrows `collections` and `universe`, and allocates what it keeps with `allocator`.
// It lives as long as the run, so nothing frees it.
resolver_init :: proc(
	r: ^Resolver,
	odin_root: string,
	collections: []Collection,
	universe: Universe,
	allocator: runtime.Allocator,
) {
	r^ = {
		odin_root   = odin_root,
		collections = collections,
		cache       = make(map[string]^Loaded_Package, allocator),
		unresolved  = make([dynamic]^Loaded_Package, allocator),
		scopes      = make([dynamic]Scope, allocator),
		allocator   = allocator,
	}
	r.builtin.symbols = universe_symbols(universe.builtin, allocator)
	r.intrinsics.symbols = universe_symbols(universe.intrinsics, allocator)
}

@(private = "file")
universe_symbols :: proc(
	entries: []Universe_Entry,
	allocator: runtime.Allocator,
) -> Package_Symbols {
	symbols := make(Package_Symbols, len(entries), allocator)
	for entry in entries {
		symbols[entry.name] = entry.kind
	}
	return symbols
}

// Parentheses and tags don't change what an expression is. The parser wraps a directive it has no
// node for, such as `#row_major`, around its operand.
unwrap_expr :: proc(expr: ^ast.Expr) -> ^ast.Expr {
	value := ast.unparen_expr(expr)
	for value != nil {
		tag := value.derived.(^ast.Tag_Expr) or_break
		value = ast.unparen_expr(tag.expr)
	}
	return value
}

is_type_expr :: proc(expr: ^ast.Expr) -> bool {
	#partial switch _ in expr.derived {
	case ^ast.Struct_Type,
	     ^ast.Union_Type,
	     ^ast.Enum_Type,
	     ^ast.Bit_Set_Type,
	     ^ast.Bit_Field_Type,
	     ^ast.Distinct_Type,
	     ^ast.Proc_Type,
	     ^ast.Pointer_Type,
	     ^ast.Multi_Pointer_Type,
	     ^ast.Array_Type,
	     ^ast.Dynamic_Array_Type,
	     ^ast.Fixed_Capacity_Dynamic_Array_Type,
	     ^ast.Map_Type,
	     ^ast.Matrix_Type,
	     ^ast.Typeid_Type,
	     ^ast.Helper_Type,
	     ^ast.Relative_Type,
	     ^ast.Poly_Type:
		return true
	}
	return false
}

// The kind of an alias declaration's right side, used at `offset` in the file `scope` describes,
// with the resolver's scopes as the enclosing procedures. Afterwards no package holds its
// declarations.
alias_kind :: proc(r: ^Resolver, value: ^ast.Expr, scope: ^File_Scope, offset: int) -> Kind {
	kind := kind_of_expr(r, value, {scope, len(r.scopes), offset})
	resolve_loaded(r)
	return kind
}

// The table of Appendix E.5.
@(private = "file")
kind_of_expr :: proc(r: ^Resolver, expr: ^ast.Expr, use: Use) -> Kind {
	value := unwrap_expr(expr)
	#partial switch v in value.derived {
	case ^ast.Ident:
		return kind_of_name(r, v.name, use)
	case ^ast.Selector_Expr:
		return kind_of_selector(r, v, use)
	case ^ast.Index_Expr, ^ast.Matrix_Index_Expr:
		return .Variable
	case ^ast.Struct_Type:
		return .Type if v.poly_params == nil else .Poly_Type
	case ^ast.Union_Type:
		return .Type if v.poly_params == nil else .Poly_Type
	case ^ast.Proc_Lit, ^ast.Proc_Group:
		return .Proc
	case ^ast.Call_Expr:
		if _, is_directive := unwrap_expr(v.expr).derived.(^ast.Basic_Directive); is_directive {
			return .Value
		}
		return CALL_KINDS[kind_of_expr(r, v.expr, use)]
	case ^ast.Ternary_When_Expr:
		return shared_kind(kind_of_expr(r, v.x, use), kind_of_expr(r, v.y, use))
	case ^ast.Ternary_If_Expr:
		return shared_kind(kind_of_expr(r, v.x, use), kind_of_expr(r, v.y, use))
	case ^ast.Basic_Lit,
	     ^ast.Comp_Lit,
	     ^ast.Unary_Expr,
	     ^ast.Binary_Expr,
	     ^ast.Type_Cast,
	     ^ast.Auto_Cast,
	     ^ast.Slice_Expr,
	     ^ast.Deref_Expr,
	     ^ast.Or_Else_Expr,
	     ^ast.Implicit_Selector_Expr:
		return .Value
	}
	return .Type if is_type_expr(value) else .Unknown
}

@(private = "file")
shared_kind :: proc(a, b: Kind) -> Kind {
	return a if a == b else .Unknown
}

@(private = "file")
kind_of_name :: proc(r: ^Resolver, name: string, use: Use) -> Kind {
	if locals, from_nested := declaring_locals(r, name, use); locals != nil {
		kind, _ := kind_in_table(r, locals, name, use.offset, from_nested)
		return kind
	}
	if kind, declared := kind_in_package(r, use.file.pkg, name); declared {
		return kind
	}
	kind, _ := kind_in_package(r, &r.builtin, name)
	return kind
}

// `a.B` names a package's symbol only when `a` is an import that nothing in scope shadows. Any
// other selector gets no case: it is a value in `Color.Red` and may be a type in `Vec3f.T`, where
// `T` is a parameter of the parametric type `Vec3f` specializes.
@(private = "file")
kind_of_selector :: proc(r: ^Resolver, selector: ^ast.Selector_Expr, use: Use) -> Kind {
	base, is_name := selector.expr.derived.(^ast.Ident)
	if !is_name || selector.op.kind != .Period || selector.field == nil {
		return .Variable
	}
	if locals, _ := declaring_locals(r, base.name, use); locals != nil {
		return .Variable
	}
	if is_declared(use.file.pkg, base.name) {
		return .Variable
	}
	imported, is_import := &use.file.imports[base.name]
	if !is_import {
		return .Variable
	}
	if !imported.looked_up {
		imported.pkg = import_package(r, use.file.dir, imported.path)
		imported.looked_up = true
	}
	if imported.pkg == nil {
		return .Unknown
	}
	kind, _ := kind_in_package(r, imported.pkg, selector.field.name)
	return kind
}

// The locals of the innermost enclosing procedure that declares `name` in scope where it is used,
// or nil. `from_nested` says the use sits in a procedure literal nested in that procedure.
@(private = "file")
declaring_locals :: proc(
	r: ^Resolver,
	name: string,
	use: Use,
) -> (
	locals: ^Symbol_Table,
	from_nested: bool,
) {
	for i := use.scope_count - 1; i >= 0; i -= 1 {
		scope := &r.scopes[i]
		if !scope.collected {
			collect_locals(scope, use.file, i + 1)
		}
		from_nested = i < use.scope_count - 1
		// Ranging over the map index itself crashes at the pin when the name is missing.
		symbols := scope.locals[name]
		for symbol in symbols {
			if is_in_scope(symbol, use.offset, from_nested) {
				return &scope.locals, from_nested
			}
		}
	}
	return nil, false
}

// The compiler skips an enclosing procedure's variables when it looks a name up from a nested
// procedure literal, and goes on to the scopes outside.
@(private = "file")
is_in_scope :: proc(symbol: Symbol, offset: int, from_nested: bool) -> bool {
	return symbol.visible_from <= offset && !(from_nested && symbol.own_proc_only)
}

@(private = "file")
is_declared :: proc(pkg: ^Loaded_Package, name: string) -> bool {
	if pkg.parsed != nil {
		return name in pkg.parsed.declared
	}
	return name in pkg.symbols
}

@(private = "file")
kind_in_package :: proc(
	r: ^Resolver,
	pkg: ^Loaded_Package,
	name: string,
) -> (
	kind: Kind,
	declared: bool,
) {
	if pkg.parsed != nil {
		return kind_in_table(r, &pkg.parsed.declared, name, 0, false)
	}
	return pkg.symbols[name]
}

// The kind the declarations of `name` that are in scope at `offset` share, or `Unknown` when they
// disagree. Every one is resolved, so the result never depends on which is asked for first.
@(private = "file")
kind_in_table :: proc(
	r: ^Resolver,
	table: ^Symbol_Table,
	name: string,
	offset: int,
	from_nested: bool,
) -> (
	kind: Kind,
	declared: bool,
) {
	group := table[name]
	for &symbol in group {
		if !is_in_scope(symbol, offset, from_nested) {
			continue
		}
		member := resolve_symbol(r, &symbol)
		kind = shared_kind(kind, member) if declared else member
		declared = true
	}
	return
}

@(private = "file")
resolve_symbol :: proc(r: ^Resolver, symbol: ^Symbol) -> Kind {
	switch symbol.state {
	case .Done:
		return symbol.kind
	case .Resolving:
		return .Unknown
	case .Fresh:
	}
	symbol.state = .Resolving
	decl := symbol.decl
	if symbol.value_index < len(decl.values) {
		use := Use{symbol.file, symbol.scope_count, decl.pos.offset}
		symbol.kind = kind_of_expr(r, decl.values[symbol.value_index], use)
	}
	symbol.state = .Done
	return symbol.kind
}

// A declaration's kind is `Variable` when it is mutable, `Value` when it is a typed constant, and
// otherwise the kind of its value.
@(private = "file")
declare :: proc(table: ^Symbol_Table, decl: ^ast.Value_Decl, file: ^File_Scope, scope_count: int) {
	for name, i in decl.names {
		ident := name.derived.(^ast.Ident) or_continue
		switch {
		case decl.is_mutable && scope_count == 0:
			declare_fixed(table, ident.name, .Variable)
		case decl.is_mutable:
			add_symbol(
				table,
				ident.name,
				{
					kind = .Variable,
					state = .Done,
					visible_from = ident.pos.offset,
					own_proc_only = !is_static(decl),
				},
			)
		case decl.type != nil:
			declare_fixed(table, ident.name, .Value)
		case:
			add_symbol(
				table,
				ident.name,
				{decl = decl, value_index = i, file = file, scope_count = scope_count},
			)
		}
	}
}

// A symbol that is in scope everywhere its table is.
@(private = "file")
declare_fixed :: proc(table: ^Symbol_Table, name: string, kind: Kind) {
	add_symbol(table, name, {kind = kind, state = .Done})
}

// A parameter, a result, or a local variable that is in scope from `visible_from` on.
@(private = "file")
declare_own_variable :: proc(table: ^Symbol_Table, name: string, visible_from: int) {
	add_symbol(
		table,
		name,
		{kind = .Variable, state = .Done, visible_from = visible_from, own_proc_only = true},
	)
}

// `@(static)` and `@(thread_local)` variables live outside the procedure's frame.
@(private = "file")
is_static :: proc(decl: ^ast.Value_Decl) -> bool {
	for attribute in decl.attributes {
		for elem in attribute.elems {
			name := elem
			if with_value, has_value := elem.derived.(^ast.Field_Value); has_value {
				name = with_value.field
			}
			ident := name.derived.(^ast.Ident) or_continue
			if ident.name == "static" || ident.name == "thread_local" {
				return true
			}
		}
	}
	return false
}

@(private = "file")
add_symbol :: proc(table: ^Symbol_Table, name: string, symbol: Symbol) {
	if name == "_" {
		return
	}
	if name not_in table {
		table[name] = make([dynamic]Symbol, table.allocator)
	}
	append(&table[name], symbol)
}

push_scope :: proc(r: ^Resolver, lit: ^ast.Proc_Lit) {
	append(&r.scopes, Scope{lit = lit})
}

pop_scope :: proc(r: ^Resolver) {
	pop(&r.scopes)
}

// Fills a scope with the locals table of Appendix E.5. Locals are scoped per procedure, not per
// block. The table is allocated with `context.allocator` and borrows the file's AST.
@(private = "file")
collect_locals :: proc(scope: ^Scope, file: ^File_Scope, scope_count: int) {
	scope.collected = true
	scope.locals = make(Symbol_Table, context.allocator)
	collector := Local_Collector {
		locals      = &scope.locals,
		file        = file,
		scope_count = scope_count,
		parents     = make([dynamic]^ast.Node, context.allocator),
	}
	defer delete(collector.parents)

	signature := ast.Visitor {
		visit = visit_signature_node,
		data  = &collector,
	}
	for list in ([2]^ast.Field_List{scope.lit.type.params, scope.lit.type.results}) {
		if list == nil {
			continue
		}
		for field in list.list {
			for name in field.names {
				if ident, is_ident := name.derived.(^ast.Ident); is_ident {
					declare_own_variable(collector.locals, ident.name, 0)
				}
			}
			ast.walk(&signature, field)
		}
	}
	body := ast.Visitor {
		visit = visit_body_node,
		data  = &collector,
	}
	ast.walk(&body, scope.lit.body)
}

@(private = "file")
Local_Collector :: struct {
	locals:      ^Symbol_Table,
	file:        ^File_Scope,
	scope_count: int,
	parents:     [dynamic]^ast.Node,
}

@(private = "file")
visit_signature_node :: proc(v: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
	c := (^Local_Collector)(v.data)
	if node == nil {
		pop(&c.parents)
		return nil
	}
	if poly, is_poly := node.derived.(^ast.Poly_Type); is_poly && poly.type != nil {
		parent := c.parents[len(c.parents) - 1] if len(c.parents) > 0 else nil
		is_type := poly_name_kind(poly, parent) == .Poly_Type
		declare_fixed(c.locals, poly.type.name, .Type if is_type else .Value)
	}
	append(&c.parents, node)
	return v
}

@(private = "file")
visit_body_node :: proc(v: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
	if node == nil {
		return nil
	}
	c := (^Local_Collector)(v.data)
	#partial switch n in node.derived {
	case ^ast.Proc_Lit:
		// Its locals belong to its own scope.
		return nil
	case ^ast.Value_Decl:
		declare(c.locals, n, c.file, c.scope_count)
	case ^ast.Range_Stmt:
		for val in n.vals {
			declare_local_variable(c.locals, val)
		}
	case ^ast.Unroll_Range_Stmt:
		declare_local_variable(c.locals, n.val0)
		declare_local_variable(c.locals, n.val1)
	case ^ast.Type_Switch_Stmt:
		if n.tag == nil {
			break
		}
		if binding, is_binding := n.tag.derived.(^ast.Assign_Stmt); is_binding {
			for name in binding.lhs {
				declare_local_variable(c.locals, name)
			}
		}
	}
	return v
}

// The parser holds a by-reference range variable as `&v`.
@(private = "file")
declare_local_variable :: proc(locals: ^Symbol_Table, name: ^ast.Expr) {
	if name == nil {
		return
	}
	#partial switch n in name.derived {
	case ^ast.Ident:
		declare_own_variable(locals, n.name, n.pos.offset)
	case ^ast.Unary_Expr:
		declare_local_variable(locals, n.expr)
	}
}

// The scope of a file the walk holds the AST of, at absolute path `path`. It loads the file's
// package through the cache, the way an import of it would. Allocates with `context.allocator`.
walked_file_scope :: proc(r: ^Resolver, file: ^ast.File, path: string) -> ^File_Scope {
	pkg := load_package(r, real_root(parent_dir(path), context.allocator))
	// A file symlink's relative imports resolve from its target's directory.
	dir := parent_dir(real_root(path, context.allocator))
	return make_file_scope(file, pkg, dir, nil, context.allocator)
}

// The symbols of the package at real path `dir`, with every one resolved.
package_symbols :: proc(r: ^Resolver, dir: string) -> Package_Symbols {
	pkg := load_package(r, dir)
	resolve_loaded(r)
	return pkg.symbols
}

// Reads the files discovery would read in `dir`, for every platform, and declares their top-level
// names. The symbols resolve on demand until `resolve_loaded` completes them.
@(private = "file")
load_package :: proc(r: ^Resolver, dir: string) -> ^Loaded_Package {
	if pkg, loaded := r.cache[dir]; loaded {
		return pkg
	}
	pkg := new(Loaded_Package, r.allocator)
	pkg.symbols = make(Package_Symbols, r.allocator)
	pkg.parsed = new(Parsed_Package, r.allocator)
	ensure(virtual.arena_init_growing(&pkg.parsed.arena) == nil, "out of memory")
	key := strings.clone(dir, r.allocator)
	r.cache[key] = pkg
	append(&r.unresolved, pkg)

	arena := virtual.arena_allocator(&pkg.parsed.arena)
	pkg.parsed.declared = make(Symbol_Table, arena)
	entries, err := list_dir(key, arena)
	if err != nil {
		return pkg
	}
	for entry in entries {
		if dir_entry_kind(entry, arena) != .Source {
			continue
		}
		source_dir := key
		if entry.type == .Symlink {
			source_dir = parent_dir(real_root(entry.fullpath, arena))
		}
		data, read_err := os.read_entire_file(entry.fullpath, arena)
		if read_err != nil {
			continue
		}
		src := string(data)
		if judge_tags(scan_header(src, arena).tags[:], "").ignored {
			continue
		}
		file: ^ast.File
		failure: Maybe(Parse_Error)
		{
			context.allocator = arena
			file, failure = parse_source(src, arena)
		}
		if failure != nil {
			continue
		}
		make_file_scope(file, pkg, source_dir, &pkg.parsed.declared, arena)
	}
	return pkg
}

// Resolves every symbol of the packages that still hold declarations, keeps the names and kinds,
// and frees the ASTs. It runs only between lookups: a symbol resolved while another is `Resolving`
// only because the loader got to it would take `Unknown` from a cycle it isn't part of.
@(private = "file")
resolve_loaded :: proc(r: ^Resolver) {
	for len(r.unresolved) > 0 {
		pkg := pop(&r.unresolved)
		for name in pkg.parsed.declared {
			kind, _ := kind_in_table(r, &pkg.parsed.declared, name, 0, false)
			pkg.symbols[strings.clone(name, r.allocator)] = kind
		}
		virtual.arena_destroy(&pkg.parsed.arena)
		free(pkg.parsed, r.allocator)
		pkg.parsed = nil
	}
}

// Records the file's imports, and its top-level declarations in `declared` when that isn't nil.
@(private = "file")
make_file_scope :: proc(
	file: ^ast.File,
	pkg: ^Loaded_Package,
	dir: string,
	declared: ^Symbol_Table,
	allocator: runtime.Allocator,
) -> ^File_Scope {
	scope := new(File_Scope, allocator)
	scope^ = {
		pkg     = pkg,
		dir     = dir,
		imports = make(map[string]Import, allocator),
	}
	for decl in file.imports {
		path, _, unquoted := strconv.unquote_string(decl.relpath.text, allocator)
		if !unquoted {
			continue
		}
		name := decl.name.text if decl.name.kind == .Ident else unaliased_import_name(path)
		scope.imports[name] = Import {
			path = path,
		}
	}
	for stmt in file.decls {
		collect_top_level(scope, declared, stmt)
	}
	return scope
}

// Declarations inside `when` and `foreign` blocks are top-level too.
@(private = "file")
collect_top_level :: proc(scope: ^File_Scope, declared: ^Symbol_Table, stmt: ^ast.Stmt) {
	if stmt == nil {
		return
	}
	#partial switch n in stmt.derived {
	case ^ast.Value_Decl:
		if declared != nil {
			declare(declared, n, scope, 0)
		}
	case ^ast.Foreign_Import_Decl:
		if n.name != nil {
			scope.imports[n.name.name] = Import {
				looked_up = true,
			}
		}
	case ^ast.When_Stmt:
		collect_top_level(scope, declared, n.body)
		collect_top_level(scope, declared, n.else_stmt)
	case ^ast.Block_Stmt:
		for inner in n.stmts {
			collect_top_level(scope, declared, inner)
		}
	case ^ast.Foreign_Block_Decl:
		collect_top_level(scope, declared, n.body)
	}
}

// The package an import names: a universe package for `base:builtin` and `base:intrinsics`, which
// odx never parses, a directory under the Odin root or an `odx.json` collection, or a path relative
// to `dir`. Nil for any other import, and for a directory that isn't there.
@(private = "file")
import_package :: proc(r: ^Resolver, dir, path: string) -> ^Loaded_Package {
	start, rest := dir, path
	if colon := strings.index_byte(path, ':'); colon >= 0 {
		collection := path[:colon]
		rest = path[colon + 1:]
		switch {
		case collection == "base" && rest == "builtin":
			return &r.builtin
		case collection == "base" && rest == "intrinsics":
			return &r.intrinsics
		case slice.contains(ODIN_CODE_DIRS[:], collection):
			if r.odin_root == "" {
				return nil
			}
			start = strings.concatenate({r.odin_root, "/", collection}, context.temp_allocator)
		case:
			found := false
			for c in r.collections {
				if c.name == collection {
					start, found = c.path, true
					break
				}
			}
			if !found {
				return nil
			}
		}
	} else if strings.has_prefix(path, "/") {
		start = ""
	}
	joined := strings.concatenate({start, "/", rest}, context.temp_allocator)
	real, err := os.get_absolute_path(joined, context.temp_allocator)
	if err != nil {
		return nil
	}
	return load_package(r, strings.trim_right(real, "/") if real != "/" else real)
}
