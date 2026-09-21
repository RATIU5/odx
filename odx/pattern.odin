package odx

import "core:fmt"
import "core:odin/ast"
import "core:strings"

// Pattern checks: `match` picks the AST node class, the other keys narrow it.
// No regex over source text, ever.
// ponytail: call reuses banned_call's alias-resolving visitor (name folds into names at load);
// metavariable templates (stage 2) wait until an idiom this cannot express is written down.

check_pattern :: proc(c: ^Ctx, p: ^Package, a: ^Active_Rule) {
	spec := &a.rule.check
	switch spec.match {
	case "call":
		check_calls(c, p, a)
	case "import":
		for f in p.files {
			for d in f.decls {
				imp, ok := d.derived.(^ast.Import_Decl)
				if !ok {continue}
				path := strings.trim(imp.relpath.text, `"`)
				if import_glob(spec.name, path) {
					report_at(c, a, &imp.node, strings.concatenate({"import of ", path}), path)
				}
			}
		}
	case "decl":
		for f in p.files {
			for d in f.decls {
				vd, ok := d.derived.(^ast.Value_Decl)
				if !ok || (spec.mutable && !vd.is_mutable) {continue}
				report_at(
					c,
					a,
					&vd.node,
					"mutable package-level variable" if vd.is_mutable else "package-level declaration",
					ident_name(vd.names[0]),
				)
			}
		}
	case "proc":
		for f in p.files {
			for d in f.decls {
				vd, ok := d.derived.(^ast.Value_Decl)
				if !ok || len(vd.values) != 1 {continue}
				pl, is_proc := vd.values[0].derived.(^ast.Proc_Lit)
				if !is_proc || (spec.exported && is_private(vd)) {continue}
				name := ident_name(vd.names[0])
				if req := spec.requires_param; req.type_suffix != "" {
					if !has_param(pl.type, req.index, req.type_suffix) {
						report_at(
							c,
							a,
							&vd.node,
							fmt.tprintf(
								"%s must take a %s as parameter %d",
								name,
								req.type_suffix,
								req.index,
							),
							name,
						)
					}
					continue
				}
				report_at(c, a, &vd.node, strings.concatenate({"procedure ", name}), name)
			}
		}
	}
}

is_private :: proc(vd: ^ast.Value_Decl) -> bool {
	for at in vd.attributes {
		for e in at.elems {
			if ident_name(e) == "private" {return true}
			if fv, ok := e.derived.(^ast.Field_Value); ok && ident_name(fv.field) == "private" {return true}
		}
	}
	return false
}

// has_param: the parameter at index (counting every name, `a, b: T` is two) has a type whose
// last identifier ends with suffix; `^Ctx` and `pkg.Ctx` count.
has_param :: proc(t: ^ast.Proc_Type, index: int, suffix: string) -> bool {
	if t == nil || t.params == nil {return false}
	i := 0
	for f in t.params.list {
		for _ in f.names {
			if i == index {return strings.has_suffix(type_name(f.type), suffix)}
			i += 1
		}
	}
	return false
}

type_name :: proc(e: ^ast.Expr) -> string {
	if e == nil {return ""}
	#partial switch x in e.derived {
	case ^ast.Ident:
		return x.name
	case ^ast.Selector_Expr:
		return x.field.name
	case ^ast.Pointer_Type:
		return type_name(x.elem)
	}
	return ""
}
