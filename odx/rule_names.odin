package odx

import "core:fmt"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strings"

// The message is allocated with the findings' allocator.
check_name :: proc(w: ^File_Walk, name: string, pos: tokenizer.Pos, kind: Name_Kind) {
	want := NAME_CASES[kind]
	if name == "_" || has_case(name, want) {
		return
	}
	message := fmt.aprintf(
		"%s '%s' isn't %s",
		NAME_KIND_LABELS[kind],
		name,
		CASE_NAMES[want],
		allocator = w.findings.allocator,
	)
	report(w, .Name_Case, pos, message)
}

// Checks a name the parser holds as an expression: an identifier, or `&v` in a by-reference range.
check_name_expr :: proc(w: ^File_Walk, expr: ^ast.Expr, kind: Name_Kind) {
	if expr == nil {
		return
	}
	#partial switch e in expr.derived {
	case ^ast.Ident:
		check_name(w, e.name, e.pos, kind)
	case ^ast.Unary_Expr:
		check_name_expr(w, e.expr, kind)
	}
}

check_value_decl_names :: proc(w: ^File_Walk, decl: ^ast.Value_Decl) {
	for name, i in decl.names {
		ident, is_ident := name.derived.(^ast.Ident)
		if !is_ident {
			continue
		}
		value: ^ast.Expr
		if len(decl.values) > 0 {
			value = ast.unparen_expr(decl.values[min(i, len(decl.values) - 1)])
		}
		kind := Name_Kind.Variable
		if !decl.is_mutable {
			kind = constant_kind(value, decl.type != nil) or_continue
		} else if is_composite_literal(value) && len(w.procs) == 0 {
			kind = .Package_Literal
		}
		check_name(w, ident.name, ident.pos, kind)
	}
}

@(private = "file")
is_composite_literal :: proc(value: ^ast.Expr) -> bool {
	if value == nil {
		return false
	}
	_, is_literal := value.derived.(^ast.Comp_Lit)
	return is_literal
}

// `known` is false for an alias or a call, which gets no case: the declaration alone doesn't say
// what its right side names.
@(private = "file")
constant_kind :: proc(expr: ^ast.Expr, has_type: bool) -> (kind: Name_Kind, known: bool) {
	value := unwrap_expr(expr)
	if value == nil {
		return
	}
	#partial switch v in value.derived {
	case ^ast.Proc_Lit:
		return .Proc, true
	case ^ast.Proc_Group:
		return .Proc_Group, true
	case ^ast.Ident, ^ast.Selector_Expr:
		return .Value_Constant, has_type
	case ^ast.Call_Expr:
		#partial switch _ in ast.unparen_expr(v.expr).derived {
		case ^ast.Ident, ^ast.Selector_Expr:
			return .Value_Constant, has_type
		}
	case ^ast.Ternary_When_Expr:
		// `int when C else i32` is as much an alias as `int` is, so the branches decide.
		then_kind, then_known := constant_kind(v.x, has_type)
		else_kind, else_known := constant_kind(v.y, has_type)
		return then_kind, then_known && else_known && then_kind == else_kind
	}
	return .Type if is_type_expr(value) && !has_type else .Value_Constant, true
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

// Without a kind, the list is a struct's or union's parameters, which are parametric with or
// without the `$`.
check_field_names :: proc(w: ^File_Walk, list: ^ast.Field_List, kind: Maybe(Name_Kind) = nil) {
	if list == nil {
		return
	}
	for field in list.list {
		field_kind := kind.? or_else param_kind(field)
		for name in field.names {
			if ident, is_ident := name.derived.(^ast.Ident); is_ident {
				check_name(w, ident.name, ident.pos, field_kind)
			}
		}
	}
}

@(private = "file")
param_kind :: proc(field: ^ast.Field) -> Name_Kind {
	if field.type != nil {
		if _, is_typeid := ast.unparen_expr(field.type).derived.(^ast.Typeid_Type); is_typeid {
			return .Poly_Type
		}
	}
	return .Poly_Value
}

check_poly_name :: proc(w: ^File_Walk, poly: ^ast.Poly_Type, parent: ^ast.Node) {
	check_name(w, poly.type.name, poly.type.pos, poly_name_kind(poly, parent))
}

// `.Poly_Type` or `.Poly_Value`, by where the `$` name sits under `parent`.
poly_name_kind :: proc(poly: ^ast.Poly_Type, parent: ^ast.Node) -> Name_Kind {
	kind := Name_Kind.Poly_Type
	is_poly :: proc(expr: ^ast.Expr, poly: ^ast.Poly_Type) -> bool {
		return rawptr(expr) == rawptr(poly)
	}
	if parent != nil {
		#partial switch p in parent.derived {
		case ^ast.Field:
			if !is_poly(p.type, poly) {
				kind = param_kind(p)
			}
		case ^ast.Array_Type:
			if is_poly(p.len, poly) {
				kind = .Poly_Value
			}
		case ^ast.Fixed_Capacity_Dynamic_Array_Type:
			if is_poly(p.capacity, poly) {
				kind = .Poly_Value
			}
		case ^ast.Matrix_Type:
			if is_poly(p.row_count, poly) || is_poly(p.column_count, poly) {
				kind = .Poly_Value
			}
		}
	}
	return kind
}

check_enum_member_names :: proc(w: ^File_Walk, fields: []^ast.Expr) {
	for field in fields {
		member := field
		if with_value, has_value := field.derived.(^ast.Field_Value); has_value {
			member = with_value.field
		}
		check_name_expr(w, member, .Enum_Member)
	}
}

check_range_names :: proc(w: ^File_Walk, vals: []^ast.Expr) {
	for val in vals {
		check_name_expr(w, val, .Loop_Variable)
	}
}

check_type_switch_names :: proc(w: ^File_Walk, tag: ^ast.Stmt) {
	if tag == nil {
		return
	}
	if binding, is_binding := tag.derived.(^ast.Assign_Stmt); is_binding {
		for name in binding.lhs {
			check_name_expr(w, name, .Type_Switch_Variable)
		}
	}
}

// The finding borrows `path`, and its message is allocated with the findings' allocator.
check_file_name :: proc(findings: ^[dynamic]Finding, path: string) {
	base := path[strings.last_index_byte(path, '/') + 1:]
	if has_case(strings.trim_suffix(base, ".odin"), .Snake) {
		return
	}
	message := fmt.aprintf("file name '%s' isn't snake_case", base, allocator = findings.allocator)
	append(findings, Finding{path = path, line = 1, col = 1, rule = .File_Name, message = message})
}

// The message is allocated with the findings' allocator.
check_package_name :: proc(file: ^Source_File, dir: string) {
	if file.name == "" {
		return
	}
	allocator := file.findings.allocator
	directory := dir[strings.last_index_byte(dir, '/') + 1:]
	message: string
	switch {
	case dir == ".":
		if has_case(file.name, .Snake) {
			return
		}
		message = fmt.aprintf("package '%s' isn't snake_case", file.name, allocator = allocator)
	case !has_case(directory, .Snake):
		message = fmt.aprintf(
			"package '%s' is in directory '%s', which isn't snake_case",
			file.name,
			directory,
			allocator = allocator,
		)
	case file.name != directory && file.name != "main":
		message = fmt.aprintf(
			"package '%s' differs from its directory '%s'",
			file.name,
			directory,
			allocator = allocator,
		)
	case:
		return
	}
	finding := Finding {
		path    = file.path,
		line    = file.package_line,
		col     = file.package_col,
		rule    = .Package_Name,
		message = message,
	}
	append(&file.findings, finding)
}
