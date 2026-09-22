package odx

import "core:fmt"
import "core:odin/ast"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

// Family B: syntax checks over the AST.

Ctx :: struct {
	root:             string,
	cfg:              ^Config,
	rb:               ^Rulebook,
	pkgs:             []Package,
	rules:            []Active_Rule,
	r:                ^Report,
	hits:             map[string]int, // config allow-list entries that matched something this run
	paths:            []string,
	graph:            Import_Graph,
	selection_reason: string,
	native_ran:       bool,
}

make_ctx :: proc(p: ^Project, paths: []string, only_topics: []string = nil) -> Ctx {
	c := Ctx {
		root  = p.root,
		cfg   = &p.cfg,
		rb    = &p.rb,
		rules = active_rules(p, only_topics),
		r     = new(Report),
		hits  = make(map[string]int),
		paths = paths,
	}
	rels := p.dirs
	if len(paths) > 0 {
		rels = select_packages(p.root, rels, paths)
		if len(rels) == 0 {fail("no packages under %v", paths)}
	}
	all := load_packages(p.root, &p.cfg, p.dirs)
	c.graph = make_import_graph(p.root, &p.cfg, all)
	c.pkgs = make([]Package, len(rels))
	for rel, i in rels {
		c.pkgs[i] = all[c.graph.by_dir[canonical(join({p.root, rel}))]]
	}
	return c
}

// Applied when a pure role has no explicit deny list.
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

// subject is the baseline key (an import path, symbol or declaration name); "" means no stable
// identity, so the finding cannot be baselined.
report :: proc(
	c: ^Ctx,
	a: ^Active_Rule,
	file: string,
	line, col: int,
	msg: string,
	subject := "",
) {
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
			statement = a.rule.statement,
			why = a.rule.why,
			subject = subject,
			blocking = true,
			fires = a.rule.fires,
			silent = a.rule.silent,
			fix_hint = a.rule.instead_of,
			ignore_syntax = ignore_syntax_of(file, a.id) if a.rule.ignorable else "",
		},
	)
}

report_at :: proc(c: ^Ctx, a: ^Active_Rule, n: ^ast.Node, msg: string, subject := "") {
	file, line, col := pos_of(c, n)
	report(c, a, file, line, col, msg, subject)
}

run_family_b :: proc(c: ^Ctx) {
	c.native_ran = true
	for &p in c.pkgs {
		c.r.summary.files += len(p.files)
		// parse errors first: the model fixes syntax before rules
		for d in p.diags {
			file, _ := rel_of(c.root, d.pos.file)
			note(c.r, "odin/syntax", "parse", file, d.pos.line, d.pos.column, d.msg)
		}
		if p.parse_result.status == .failed {
			if len(p.diags) ==
			   0 {tool_error(c.r, "cannot parse %s: %s", p.rel, p.parse_result.reason)}
			continue
		}
		for f in p.files {
			check_vet_disables(c, f)
		}
		// every `match: call` rule shares one AST walk per file (the only check that walks)
		calls := make([dynamic]^Active_Rule, context.temp_allocator)
		for &a in c.rules {
			if a.rule.check.kind == .pattern &&
			   a.rule.check.match == "call" &&
			   check_applies(c.cfg, &a.rule.check, p.role) {append(&calls, &a)}
		}
		if len(calls) > 0 {check_calls(c, &p, calls[:])}
		for &a in c.rules {
			spec := &a.rule.check
			if !check_applies(c.cfg, spec, p.role) {continue}
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
						p.rel if p.rel != "" else ".",
					)
				}
			case .vet_tag:
				check_explicit_allocators(c, &p, &a)
			case .banned_import:
				check_imports(c, &p, &a)
			case .pattern:
				check_pattern(c, &p, &a)
			case .require_attribute:
			// family C (docfmt.odin)
			}
		}
	}
}

// `!x` is kept as written.
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

// `#+feature` opt-outs need a same-line `// reason:`.
check_vet_disables :: proc(c: ^Ctx, f: ^ast.File) {
	// a comment token, not a substring of the line: `// reason:` inside a string literal is not a reason
	has_reason :: proc(f: ^ast.File, line: int) -> bool {
		for g in f.comments {
			for ct in g.list {
				if ct.pos.line == line && strings.has_prefix(ct.text, "// reason:") {return true}
			}
		}
		return false
	}
	for tok in f.tags {
		t := strings.trim_space(strings.trim_prefix(tok.text, "#+"))
		if !strings.has_prefix(t, "feature") {continue}
		if has_reason(f, tok.pos.line) {continue}
		file, _ := rel_of(c.root, f.fullpath)
		note(
			c.r,
			"odx/feature-optout",
			"vet_tags",
			file,
			tok.pos.line,
			1,
			strings.concatenate(
				{
					"`",
					tok.text,
					"` opts out of a compiler guarantee; add `// reason: <why>` on that line",
				},
			),
		)
	}
	// `#+vet !x` silently defeats -vet: never ignorable, only allow-listable in config.
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

// odin.explicit_allocators: "all" extends the requirement beyond pure/service, "off" drops it.
check_explicit_allocators :: proc(c: ^Ctx, p: ^Package, a: ^Active_Rule) {
	for f in p.files {
		if slice.contains(vet_tag_names(f), "explicit-allocators") {continue}
		file, _ := rel_of(c.root, f.fullpath)
		report(c, a, file, 1, 1, "file must start with `#+vet explicit-allocators`", file)
	}
}

// Import strings are not paths: `core:*` means any core package, `core:sys/*` any package under
// core:sys. A trailing `*` is a prefix match, anything else is exact.
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

Walk :: struct {
	c:       ^Ctx,
	rules:   []^Active_Rule, // every call rule that applies to the package
	aliases: map[string]string, // local import name -> import path
}

// Matches `pkg.name` or bare `name` calls; aliases resolved per file, best effort.
// One walk per file dispatches to every rule, so the cost is O(files), not O(files × rules).
check_calls :: proc(c: ^Ctx, p: ^Package, rules: []^Active_Rule) {
	for f in p.files {
		w := Walk{c, rules, make(map[string]string, context.temp_allocator)}
		for d in f.decls {
			if imp, ok := d.derived.(^ast.Import_Decl); ok {
				path, _, valid := strconv.unquote_string(imp.relpath.text, context.temp_allocator)
				if !valid {continue}
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
	if name == "" {return v}
	for a in w.rules {
		if slice.contains(
			a.rule.check.names,
			name,
		) {report_at(w.c, a, n, strings.concatenate({"call to ", name}), name)}
	}
	return v
}

// Only on a full run: a narrowed scan would report false staleness. may_import is policy, not an
// exception list, so it is not counted.
report_stale_config :: proc(c: ^Ctx) {
	for i in 0 ..< len(c.cfg.odin.allowed_vet_disables) {
		key := fmt.tprintf("odin.allowed_vet_disables[%d]", i)
		if c.hits[key] > 0 {continue}
		// ponytail: key path, not a line number; core:encoding/json keeps no positions
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

ident_name :: proc(e: ^ast.Expr) -> string {
	if e == nil {return ""}
	if id, ok := e.derived.(^ast.Ident); ok {return id.name}
	return ""
}
