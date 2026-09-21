package odx

import "core:fmt"
import "core:odin/ast"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// Family B: syntax checks over the AST, one dispatch per active rule kind.

// Ctx is the one value every check, family and command works on; make_ctx builds it.
Ctx :: struct {
	root:  string,
	cfg:   ^Config,
	rb:    ^Rulebook,
	pkgs:  []Package,
	rules: []Active_Rule,
	r:     ^Report,
	hits:  map[string]int, // config allow-list entries that matched something this run (20.2)
}

// make_ctx selects and parses the packages under paths (all when empty) for a loaded project.
make_ctx :: proc(p: ^Project, paths: []string, only_topics: []string = nil) -> Ctx {
	c := Ctx {
		root  = p.root,
		cfg   = &p.cfg,
		rb    = &p.rb,
		rules = active_rules(p, only_topics),
		r     = new(Report),
		hits  = make(map[string]int),
	}
	rels := p.dirs
	if len(paths) > 0 {
		rels = select_packages(p.root, rels, paths)
		if len(rels) == 0 {fail("no packages under %v", paths)}
	}
	c.pkgs = load_packages(p.root, &p.cfg, rels)
	return c
}

// DEFAULT_DENY_PURE is applied when a pure role has no explicit deny list (17.3).
DEFAULT_DENY_PURE := []string {
	"core:os",
	"core:os/*",
	"core:net",
	"core:sys/*",
	"core:thread",
	"core:sync",
	"core:dynlib",
	"core:c/libc",
	"vendor:*",
}
ALWAYS_ALLOWED := []string{"base:*", "core:testing"}
TEST_ALLOWED := []string{"core:testing", "core:log", "core:fmt"}

pos_of :: proc(c: ^Ctx, n: ^ast.Node) -> (file: string, line, col: int) {
	file, _ = rel_of(c.root, n.pos.file)
	return file, n.pos.line, n.pos.column
}

// report is the one way a check emits a finding for a rule.
report :: proc(c: ^Ctx, a: ^Active_Rule, file: string, line, col: int, msg: string) {
	append(
		&c.r.violations,
		Violation {
			file = file,
			line = line,
			col = col,
			rule = a.id,
			severity = a.rule.severity,
			check = fmt.aprint(a.rule.check.kind),
			message = msg,
			ignorable = a.rule.ignorable,
			class = a.rule.class,
		},
	)
}

// report_at is report for an AST node.
report_at :: proc(c: ^Ctx, a: ^Active_Rule, n: ^ast.Node, msg: string) {
	file, line, col := pos_of(c, n)
	report(c, a, file, line, col, msg)
}

run_family_b :: proc(c: ^Ctx) {
	for &p in c.pkgs {
		// parse errors first (17.10: the model fixes syntax before rules)
		for d in p.diags {
			file, _ := rel_of(c.root, d.pos.file)
			note(c.r, "odin/syntax", "parse", file, d.pos.line, d.pos.column, d.msg)
		}
		for f in p.files {
			c.r.summary.files += 1
			check_vet_disables(c, f)
		}
		for &a in c.rules {
			spec := &a.rule.check
			if !role_applies(spec, p.role) {continue}
			switch spec.kind {
			case .path_role:
				if p.role_count == 0 {
					report(
						c,
						&a,
						p.rel if p.rel != "" else ".",
						1,
						1,
						"package directory has no role in odx.json5",
					)
				}
			case .vet_tag:
				check_explicit_allocators(c, &p, &a)
			case .banned_import:
				check_imports(c, &p, &a)
			case .banned_construct:
				check_construct(c, &p, &a)
			case .banned_call:
				check_calls(c, &p, &a)
			case .manual, .require_attribute:
			// manual never runs; require_attribute is family C (docfmt.odin)
			}
		}
	}
}

// vet_tag_names lists the names on a file's `#+vet` tags (`!x` kept as written).
vet_tag_names :: proc(f: ^ast.File) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for tok in f.tags {
		t := strings.trim_space(strings.trim_prefix(tok.text, "#+"))
		if strings.has_prefix(t, "vet") {
			append(&out, ..strings.fields(t[len("vet"):], context.temp_allocator))
		}
	}
	return out[:]
}

// 17.2: `#+vet !x` silently defeats -vet; never ignorable, only allow-listable in config.
check_vet_disables :: proc(c: ^Ctx, f: ^ast.File) {
	for name in vet_tag_names(f) {
		if !strings.has_prefix(name, "!") {continue}
		if i, ok := slice.linear_search(c.cfg.odin.allowed_vet_disables, name[1:]); ok {
			c.hits[fmt.aprintf("odin.allowed_vet_disables[%d]", i)] += 1
			continue
		}
		file, _ := rel_of(c.root, f.fullpath)
		note(
			c.r,
			"odx/vet-disable",
			"vet_tags",
			file,
			f.tags[0].pos.line,
			1,
			strings.concatenate(
				{
					"file tag ",
					name,
					" disables a vet check; not ignorable, use odin.allowed_vet_disables",
				},
			),
		)
	}
}

// vet_tag rule: the file must carry `#+vet explicit-allocators`. odin.explicit_allocators
// widens ("all") or silences ("off") the rule's own role list.
check_explicit_allocators :: proc(c: ^Ctx, p: ^Package, a: ^Active_Rule) {
	switch c.cfg.odin.explicit_allocators {
	case .off:
		return
	case .all:
	case .pure:
		if p.role != "pure" && p.role != "service" {return}
	}
	for f in p.files {
		if slice.contains(vet_tag_names(f), "explicit-allocators") {continue}
		file, _ := rel_of(c.root, f.fullpath)
		report(c, a, file, 1, 1, "file must start with `#+vet explicit-allocators`")
	}
}

// import_target describes what an import string points at: a collection path or a project role.
import_target :: proc(c: ^Ctx, p: ^Package, path: string) -> (label: string, role: string) {
	coll, _, rest := strings.partition(path, ":")
	base, sub := p.dir, path // relative import
	if rest != "" {
		cpath, is_project := c.cfg.odin.collections[coll]
		if !is_project {return path, ""} 	// core:, base:, vendor: or an unknown collection
		base, sub = join({c.root, cpath}), rest
	}
	dir, _ := filepath.clean(join({base, sub}), context.temp_allocator)
	rel, _ := rel_of(c.root, dir)
	role, _ = role_of(c.cfg, rel)
	return rel, role
}

check_imports :: proc(c: ^Ctx, p: ^Package, a: ^Active_Rule) {
	layer, has_layer := c.cfg.layering[p.role]
	if !has_layer {return} 	// no layering entry = role imports freely
	deny := layer.deny
	for f in p.files {
		is_test := strings.has_suffix(f.fullpath, "_test.odin")
		for d in f.decls {
			imp, ok := d.derived.(^ast.Import_Decl)
			if !ok {continue}
			path := strings.trim(imp.relpath.text, `"`) // 17.20: text includes the quotes
			label, target_role := import_target(c, p, path)
			allowed :=
				import_matches(ALWAYS_ALLOWED, path) ||
				(is_test && slice.contains(TEST_ALLOWED, path))
			for m in layer.may_import {
				allowed ||= (target_role != "" && m == target_role) || import_glob(m, path)
			}
			if allowed && !import_matches(deny, path) {continue}
			what :=
				label if target_role == "" else strings.concatenate({label, " (role ", target_role, ")"}, context.temp_allocator)
			report_at(
				c,
				a,
				&imp.node,
				strings.concatenate({p.role, " package may not import ", what}),
			)
		}
	}
}

// import_glob: import strings are not paths; `core:*` means any core package, `core:sys/*` any
// package under core:sys. A trailing `*` is a prefix match, anything else is exact.
import_glob :: proc(pattern, path: string) -> bool {
	if strings.has_suffix(
		pattern,
		"*",
	) {return strings.has_prefix(path, pattern[:len(pattern) - 1])}
	return pattern == path
}

import_matches :: proc(globs: []string, path: string) -> bool {
	for g in globs {if import_glob(g, path) {return true}}
	return false
}

// banned_construct: mutable_global and foreign are declaration-level; using and
// no_bounds_check need a full walk.
check_construct :: proc(c: ^Ctx, p: ^Package, a: ^Active_Rule) {
	in_role := strings.concatenate({" in a ", p.role, " package"}, context.temp_allocator)
	for f in p.files {
		switch a.rule.check.construct {
		case .mutable_global:
			for d in f.decls {
				if vd, ok := d.derived.(^ast.Value_Decl); ok && vd.is_mutable {
					report_at(
						c,
						a,
						&vd.node,
						strings.concatenate({"mutable package-level variable", in_role}),
					)
				}
			}
		case .foreign_decl:
			for d in f.decls {
				#partial switch fd in d.derived {
				case ^ast.Foreign_Import_Decl:
					report_at(c, a, &fd.node, strings.concatenate({"foreign import", in_role}))
				case ^ast.Foreign_Block_Decl:
					report_at(c, a, &fd.node, strings.concatenate({"foreign block", in_role}))
				}
			}
		case .using_stmt, .no_bounds_check:
			walk := Walk{c, a, nil}
			v := ast.Visitor {
				visit = visit_construct,
				data  = &walk,
			}
			ast.walk(&v, f)
		}
	}
}

// Walk is the visitor payload shared by the node-level checks.
Walk :: struct {
	c:       ^Ctx,
	a:       ^Active_Rule,
	aliases: map[string]string, // banned_call: local import name -> import path
}

visit_construct :: proc(v: ^ast.Visitor, n: ^ast.Node) -> ^ast.Visitor {
	if n == nil {return nil}
	w := cast(^Walk)v.data
	hit := false
	#partial switch w.a.rule.check.construct {
	case .using_stmt:
		_, hit = n.derived.(^ast.Using_Stmt)
	case .no_bounds_check:
		pl, is_proc := n.derived.(^ast.Proc_Lit)
		hit = .No_Bounds_Check in n.state_flags || (is_proc && .No_Bounds_Check in pl.tags)
	}
	if hit {report_at(w.c, w.a, n, fmt.tprint(w.a.rule.check.construct))}
	return v
}

// banned_call: `pkg.name` or bare `name` calls, aliases resolved per file (17.3, best effort).
check_calls :: proc(c: ^Ctx, p: ^Package, a: ^Active_Rule) {
	for f in p.files {
		w := Walk{c, a, make(map[string]string, context.temp_allocator)}
		for d in f.decls {
			if imp, ok := d.derived.(^ast.Import_Decl); ok {
				path := strings.trim(imp.relpath.text, `"`)
				w.aliases[imp.name.text if imp.name.text != "" else import_pkg_name(path)] = path
			}
		}
		v := ast.Visitor {
			visit = visit_call,
			data  = &w,
		}
		ast.walk(&v, f)
	}
}

// import_pkg_name: the default local name of an import path: "core:os" -> os, "../core" -> core.
import_pkg_name :: proc(path: string) -> string {
	_, _, rest := strings.partition(path, ":")
	return filepath.base(rest if rest != "" else path)
}

visit_call :: proc(v: ^ast.Visitor, n: ^ast.Node) -> ^ast.Visitor {
	if n == nil {return nil}
	w := cast(^Walk)v.data
	call, ok := n.derived.(^ast.Call_Expr)
	if !ok {return v}
	name: string
	#partial switch e in call.expr.derived {
	case ^ast.Ident:
		name = e.name
	case ^ast.Selector_Expr:
		if pkg, isid := e.expr.derived.(^ast.Ident); isid {
			// canonical form is the import's last path element: `fs.read` with `import fs "core:os"` -> os.read
			path, aliased := w.aliases[pkg.name]
			name = strings.concatenate(
				{import_pkg_name(path) if aliased else pkg.name, ".", e.field.name},
				context.temp_allocator,
			)
		}
	}
	if name != "" && slice.contains(w.a.rule.check.names, name) {
		report_at(w.c, w.a, n, strings.concatenate({"call to ", name}))
	}
	return v
}

// report_stale_config: every exception-list entry with zero hits (20.2). Only on a full run: a
// narrowed scan would report false staleness. may_import is policy, not an exception list, so
// it is not counted.
report_stale_config :: proc(c: ^Ctx) {
	for i in 0 ..< len(c.cfg.odin.allowed_vet_disables) {
		key := fmt.tprintf("odin.allowed_vet_disables[%d]", i)
		if c.hits[key] > 0 {continue}
		// ponytail: key path, not a line number; core:encoding/json keeps no positions (20.7)
		note(
			c.r,
			"odx/stale-config-entry",
			"config",
			CONFIG_FILE,
			1,
			1,
			strings.concatenate({key, " matched nothing"}),
		)
	}
}
